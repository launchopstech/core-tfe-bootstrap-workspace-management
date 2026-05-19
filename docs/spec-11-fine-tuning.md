# Spec-11: Fine-Tuning Pipeline

**Status:** `[ ] post-mvp — not started`
**Phase:** Post-MVP
**Depends on:** `spec-05-ai-storage`, `spec-07-ecr`, `iam`, `vpc`, `spec-01-bedrock`
**Blocks:** nothing (enhancement path — base RAG pipeline must be validated first)
**Repo(s):** core-tfe-bootstrap-workspace-management

> **Prerequisite before implementing:** `spec-05-ai-storage` must be deployed AND at least
> one client must have validated the base RAG pipeline (spec-06-vector-store) in production.
> Fine-tuning adds complexity that is only justified when RAG + system prompts are insufficient
> for a client's behavioral requirements.

---

## Goal

Provision a LoRA/QLoRA fine-tuning pipeline that:
- Trains lightweight adapter weights on client-specific data (not the full model)
- Stores versioned adapters in the `ai-storage` adapter-weights bucket (spec-05)
- Registers adapters in SageMaker Model Registry for versioned deployment
- Orchestrates the full pipeline via Step Functions (validate → train → eval → register)
- Costs under $10/training run on Spot GPU instances

---

## Context

### Why LoRA/QLoRA, Not Full Fine-Tuning

Full model fine-tuning requires:
- Terabytes of GPU memory (impractical for 70B+ models)
- Weeks of compute time
- Massive cost ($10K–$100K+ per run)

LoRA (Low-Rank Adaptation) instead:
- Freezes the base model weights entirely
- Trains only small adapter matrices (rank `r` << model dimension)
- Adapter size: 10–100MB vs tens of GB for full weights
- Train on a single ml.g4dn.xlarge (~$0.53/hr Spot) in 1–4 hours = **under $10/run**
- Swap adapters at runtime without reloading the base model

**From Decagon research**: Decagon uses task-expert models fine-tuned on domain-specific
tasks. Each expert handles one sub-task (intent detection, response generation, hallucination
check) rather than one giant model handling everything. LoRA adapters map directly to this
pattern — one adapter per task/domain/client.

### When Fine-Tuning is Justified

Use fine-tuning when:
- **Tone/brand voice** — the model must sound like a specific brand, and system prompts aren't sufficient
- **Custom schema adherence** — the model must output proprietary JSON/XML formats reliably
- **Domain jargon** — specialized terminology that RAG retrieval can't compensate for
- **Instruction following failure** — the base model ignores system prompt instructions in edge cases

Do NOT fine-tune for:
- Knowledge injection — use RAG (spec-06)
- Factual updates — update the knowledge base, not the model
- Simple behavior changes — update the system prompt first

### Architecture

```
Client uploads training data to S3 (ai-storage: training-data bucket)
         │
         ▼
S3 Event → EventBridge → Step Functions execution
         │
         ▼
Step 1: Data Validation Lambda
  - Check format (JSONL: {"prompt": "...", "completion": "..."})
  - Check minimum sample count (>100 examples)
  - Fail fast with clear error if invalid
         │
         ▼
Step 2: SageMaker Training Job (HuggingFace + PEFT)
  - Instance: ml.g4dn.xlarge (Spot)
  - Script: train.py (LoRA via PEFT library)
  - Input: S3 training data
  - Output: adapter weights → S3 adapter-weights bucket
         │
         ▼
Step 3: Evaluation Lambda
  - Load adapter + base model
  - Run eval dataset
  - Check metric (perplexity, ROUGE, task-specific)
  - Pass/fail gate
         │
         ▼ (if pass)
Step 4: SageMaker Model Registry
  - Register adapter as a new model version
  - Status: PendingManualApproval (human reviews before prod deploy)
         │
         ▼
Step 5: Notification
  - SNS → email/Slack with training results and registry link
  - If eval failed: alert with failure reason, no registration

Runtime adapter loading (in forge-core-ai / ai-gateway):
  - LiteLLM loads base model + LoRA adapter via PEFT
  - Adapter path = S3 URI from registry
  - Hot-swap: load adapter weights on ECS task startup
  - No base model reload needed
```

---

## `accounts.tf.json` Contract

```json
"ai-fine-tuning": {
  "ai_fine_tuning_config_json": {
    "base_model": "meta-llama/Llama-3-8B",
    "training_instance": "ml.g4dn.xlarge",
    "use_spot": true,
    "max_spot_wait_seconds": 3600,
    "max_runtime_seconds": 14400,
    "lora_config": {
      "r": 16,
      "lora_alpha": 32,
      "target_modules": ["q_proj", "v_proj"],
      "lora_dropout": 0.05,
      "task_type": "CAUSAL_LM"
    },
    "training": {
      "epochs": 3,
      "batch_size": 4,
      "gradient_accumulation_steps": 4,
      "learning_rate": 0.0002,
      "warmup_ratio": 0.03,
      "fp16": true
    },
    "pipeline": {
      "trigger": "manual",
      "eval_metric": "perplexity",
      "eval_threshold": 10.0,
      "auto_register": false,
      "notify_on_completion": true
    },
    "schedule": {
      "enabled": false,
      "cron": "cron(0 2 ? * MON *)"
    }
  }
}
```

**`trigger`**: `"manual"` — training only runs when explicitly triggered (safest default).
Set to `"s3_event"` to trigger automatically when new training data lands in S3.

**`auto_register`**: `false` — human reviews adapter quality before it's approved for production.
Set to `true` only when eval metrics are well-established and trusted.

**`use_spot`**: Always `true` for training — Spot interruption just restarts the job, not a
loss of data (SageMaker checkpoints to S3 automatically).

---

## Workspace Structure

```
workspaces/ai-fine-tuning/
  main.tf              ← SageMaker resources, Step Functions, EventBridge
  iam.tf               ← SageMaker execution role, Step Functions role, Lambda role
  variables.tf         ← ai_fine_tuning_config_json (decoded)
  outputs.tf           ← pipeline_arn, model_package_group_name, adapter_bucket_prefix
  data.tf              ← ai-storage, ecr, iam, vpc outputs
  training/
    train.py           ← LoRA training script (HuggingFace PEFT)
    requirements.txt   ← transformers, peft, datasets, trl
  evaluation/
    eval.py            ← Perplexity / task metric evaluation script
```

---

## Sample Terraform

### SageMaker Model Package Group (Adapter Registry)

```hcl
locals {
  config = jsondecode(var.ai_fine_tuning_config_json)
}

resource "aws_sagemaker_model_package_group" "adapters" {
  model_package_group_name        = "${var.client_id}-${var.env}-lora-adapters"
  model_package_group_description = "LoRA adapter versions for ${var.client_id} ${var.env}"

  tags = merge(var.tags, {
    blueprint  = "ai-fine-tuning"
    base_model = local.config.base_model
  })
}
```

### SageMaker Training Job (triggered by Step Functions)

```hcl
# The training job is NOT a persistent resource — it's created on-demand by Step Functions.
# This resource defines the template; Step Functions calls CreateTrainingJob API.

# SageMaker execution role
resource "aws_iam_role" "sagemaker_exec" {
  name = "${var.client_id}-${var.env}-sagemaker-exec"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "sagemaker.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "sagemaker_exec" {
  name = "sagemaker-exec-policy"
  role = aws_iam_role.sagemaker_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Read training data from ai-storage training-data bucket
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:ListBucket"]
        Resource = [
          data.tfe_outputs.ai_storage.outputs.bucket_arns["training_data"],
          "${data.tfe_outputs.ai_storage.outputs.bucket_arns["training_data"]}/*"
        ]
      },
      {
        # Write adapter weights to ai-storage adapter-weights bucket
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:GetObject"]
        Resource = ["${data.tfe_outputs.ai_storage.outputs.bucket_arns["adapter_weights"]}/*"]
      },
      {
        # Write checkpoints (Spot interruption recovery)
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:GetObject", "s3:DeleteObject"]
        Resource = ["${data.tfe_outputs.ai_storage.outputs.bucket_arns["model_artifacts"]}/*"]
      },
      {
        # CloudWatch logs
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = ["arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/sagemaker/*"]
      },
      {
        # KMS for encrypted S3 buckets
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
        Resource = [data.tfe_outputs.secure_baseline.outputs.kms_key_arn]
      }
    ]
  })
}
```

### Step Functions State Machine

```hcl
resource "aws_sfn_state_machine" "fine_tuning_pipeline" {
  name     = "${var.client_id}-${var.env}-fine-tuning-pipeline"
  role_arn = aws_iam_role.step_functions.arn

  definition = jsonencode({
    Comment = "LoRA fine-tuning pipeline: validate → train → eval → register"
    StartAt = "ValidateData"
    States = {
      ValidateData = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.data_validator.function_name
          Payload = { "$.input" = "$" }
        }
        ResultPath = "$.validation"
        Next       = "StartTraining"
        Catch = [{
          ErrorEquals = ["ValidationError"]
          Next        = "NotifyFailure"
          ResultPath  = "$.error"
        }]
      }

      StartTraining = {
        Type     = "Task"
        Resource = "arn:aws:states:::sagemaker:createTrainingJob.sync"
        Parameters = {
          TrainingJobName                = "States.Format('{}-{}-lora-{}', '${var.client_id}', '${var.env}', '$.executionId')"
          AlgorithmSpecification = {
            TrainingImage     = "763104351884.dkr.ecr.${var.region}.amazonaws.com/huggingface-pytorch-training:2.0.0-transformers4.28.1-gpu-py310-cu118-ubuntu20.04"
            TrainingInputMode = "File"
          }
          RoleArn = aws_iam_role.sagemaker_exec.arn
          ResourceConfig = {
            InstanceType   = local.config.training_instance
            InstanceCount  = 1
            VolumeSizeInGB = 50
          }
          StoppingCondition = {
            MaxRuntimeInSeconds         = local.config.max_runtime_seconds
            MaxWaitTimeInSeconds        = local.config.use_spot ? local.config.max_spot_wait_seconds : null
          }
          EnableManagedSpotTraining = local.config.use_spot
          CheckpointConfig = {
            S3Uri = "s3://${data.tfe_outputs.ai_storage.outputs.bucket_names["model_artifacts"]}/${var.client_id}/${var.env}/checkpoints/"
          }
          HyperParameters = {
            base_model                  = local.config.base_model
            lora_r                      = tostring(local.config.lora_config.r)
            lora_alpha                  = tostring(local.config.lora_config.lora_alpha)
            lora_dropout                = tostring(local.config.lora_config.lora_dropout)
            num_train_epochs            = tostring(local.config.training.epochs)
            per_device_train_batch_size = tostring(local.config.training.batch_size)
            learning_rate               = tostring(local.config.training.learning_rate)
          }
          OutputDataConfig = {
            S3OutputPath = "s3://${data.tfe_outputs.ai_storage.outputs.bucket_names["adapter_weights"]}/${var.client_id}/${var.env}/"
            KmsKeyId     = data.tfe_outputs.secure_baseline.outputs.kms_key_arn
          }
          InputDataConfig = [{
            ChannelName = "training"
            DataSource = {
              S3DataSource = {
                S3DataType = "S3Prefix"
                S3Uri      = "$.input.s3_training_data_uri"
              }
            }
          }]
        }
        ResultPath = "$.training"
        Next       = "EvaluateAdapter"
        Catch = [{
          ErrorEquals = ["States.ALL"]
          Next        = "NotifyFailure"
          ResultPath  = "$.error"
        }]
      }

      EvaluateAdapter = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.evaluator.function_name
          Payload = {
            "adapter_s3_uri.$"   = "$.training.ModelArtifacts.S3ModelArtifacts"
            "eval_metric"        = local.config.pipeline.eval_metric
            "eval_threshold"     = local.config.pipeline.eval_threshold
          }
        }
        ResultPath = "$.evaluation"
        Next       = "EvalPassed"
        Catch = [{
          ErrorEquals = ["States.ALL"]
          Next        = "NotifyFailure"
          ResultPath  = "$.error"
        }]
      }

      EvalPassed = {
        Type = "Choice"
        Choices = [{
          Variable      = "$.evaluation.Payload.passed"
          BooleanEquals = true
          Next          = "RegisterAdapter"
        }]
        Default = "NotifyEvalFailure"
      }

      RegisterAdapter = {
        Type     = "Task"
        Resource = "arn:aws:states:::sagemaker:createModelPackage.sync"
        Parameters = {
          ModelPackageGroupName = aws_sagemaker_model_package_group.adapters.model_package_group_name
          ModelPackageDescription = "States.Format('LoRA adapter trained on {} | {} = {}', '$.input.dataset_name', '${local.config.pipeline.eval_metric}', '$.evaluation.Payload.score')"
          ModelApprovalStatus   = local.config.pipeline.auto_register ? "Approved" : "PendingManualApproval"
          InferenceSpecification = {
            Containers = [{
              Image = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com/${var.client_id}-${var.env}-ai-engine:latest"
              ModelDataUrl = "$.training.ModelArtifacts.S3ModelArtifacts"
            }]
            SupportedContentTypes     = ["application/json"]
            SupportedResponseMIMETypes = ["application/json"]
          }
        }
        ResultPath = "$.registration"
        Next       = "NotifySuccess"
      }

      NotifySuccess = {
        Type     = "Task"
        Resource = "arn:aws:states:::sns:publish"
        Parameters = {
          TopicArn = aws_sns_topic.fine_tuning_notifications.arn
          Message  = "States.Format('Fine-tuning complete for ${var.client_id}-${var.env}. Eval score: {}. Status: PendingManualApproval in SageMaker Model Registry.', '$.evaluation.Payload.score')"
          Subject  = "Fine-tuning pipeline succeeded — adapter ready for review"
        }
        End = true
      }

      NotifyEvalFailure = {
        Type     = "Task"
        Resource = "arn:aws:states:::sns:publish"
        Parameters = {
          TopicArn = aws_sns_topic.fine_tuning_notifications.arn
          Message  = "States.Format('Fine-tuning eval FAILED for ${var.client_id}-${var.env}. Score {} did not meet threshold ${tostring(local.config.pipeline.eval_threshold)}.', '$.evaluation.Payload.score')"
          Subject  = "Fine-tuning pipeline: eval failed — adapter NOT registered"
        }
        End = true
      }

      NotifyFailure = {
        Type     = "Task"
        Resource = "arn:aws:states:::sns:publish"
        Parameters = {
          TopicArn = aws_sns_topic.fine_tuning_notifications.arn
          Message  = "States.Format('Fine-tuning pipeline FAILED for ${var.client_id}-${var.env}. Error: {}', '$.error')"
          Subject  = "Fine-tuning pipeline: error — check CloudWatch logs"
        }
        End = true
      }
    }
  })
}
```

### Training Script (illustrative, lives in workspaces/ai-fine-tuning/training/)

```python
# train.py — runs inside SageMaker training container
# HuggingFace PEFT + TRL for LoRA fine-tuning

import os
import json
from datasets import load_dataset
from transformers import AutoModelForCausalLM, AutoTokenizer, TrainingArguments
from peft import LoraConfig, get_peft_model
from trl import SFTTrainer

# SageMaker injects these environment variables
model_name    = os.environ["SM_HP_BASE_MODEL"]       # e.g. meta-llama/Llama-3-8B
output_dir    = os.environ["SM_MODEL_DIR"]            # local path → uploaded to S3
training_data = os.environ["SM_CHANNEL_TRAINING"]    # local path to training JSONL

lora_config = LoraConfig(
    r=int(os.environ["SM_HP_LORA_R"]),
    lora_alpha=int(os.environ["SM_HP_LORA_ALPHA"]),
    target_modules=["q_proj", "v_proj"],
    lora_dropout=float(os.environ["SM_HP_LORA_DROPOUT"]),
    task_type="CAUSAL_LM"
)

model = AutoModelForCausalLM.from_pretrained(model_name, device_map="auto")
model = get_peft_model(model, lora_config)
model.print_trainable_parameters()  # Shows: e.g. "trainable params: 4,194,304 (0.5% of 7B)"

tokenizer = AutoTokenizer.from_pretrained(model_name)
dataset   = load_dataset("json", data_files=f"{training_data}/train.jsonl", split="train")

trainer = SFTTrainer(
    model=model,
    train_dataset=dataset,
    dataset_text_field="text",
    args=TrainingArguments(
        output_dir=output_dir,
        num_train_epochs=int(os.environ.get("SM_HP_NUM_TRAIN_EPOCHS", 3)),
        per_device_train_batch_size=int(os.environ.get("SM_HP_PER_DEVICE_TRAIN_BATCH_SIZE", 4)),
        learning_rate=float(os.environ.get("SM_HP_LEARNING_RATE", 2e-4)),
        fp16=True,
        save_strategy="epoch",
        logging_steps=10,
    )
)

trainer.train()
# Saves adapter weights to output_dir → SageMaker uploads to S3 adapter-weights bucket
trainer.save_model(output_dir)
```

### Runtime Adapter Loading (in forge-core-ai — not Terraform)

```python
# In forge-core-ai: load LoRA adapter weights on ECS task startup
# Adapter S3 path comes from SageMaker Model Registry via env var

import os
from peft import PeftModel
from transformers import AutoModelForCausalLM

ADAPTER_S3_URI = os.environ.get("LORA_ADAPTER_S3_URI")  # injected from ECS task env

if ADAPTER_S3_URI:
    # Download adapter weights from S3 (small: 10-100MB)
    # Use boto3 to sync adapter weights to local /tmp
    base_model = AutoModelForCausalLM.from_pretrained(BASE_MODEL_NAME)
    model = PeftModel.from_pretrained(base_model, ADAPTER_S3_URI)
    model.merge_and_unload()  # Merge adapter into model for inference speed
else:
    model = AutoModelForCausalLM.from_pretrained(BASE_MODEL_NAME)
```

---

## IAM Permissions Required (Bootstrap Role)

```
sagemaker:CreateTrainingJob, sagemaker:DescribeTrainingJob, sagemaker:StopTrainingJob
sagemaker:CreateModelPackageGroup, sagemaker:CreateModelPackage, sagemaker:ListModelPackages
states:CreateStateMachine, states:DeleteStateMachine, states:StartExecution
sns:CreateTopic, sns:Subscribe, sns:Publish
lambda:CreateFunction, lambda:DeleteFunction
events:PutRule, events:PutTargets, events:DeleteRule
iam:CreateRole, iam:AttachRolePolicy, iam:PassRole
```

---

## Outputs

```hcl
output "pipeline_arn" {
  description = "Step Functions state machine ARN — trigger manually or via S3 event"
  value       = aws_sfn_state_machine.fine_tuning_pipeline.arn
}

output "model_package_group_name" {
  description = "SageMaker Model Package Group name — view approved adapters here"
  value       = aws_sagemaker_model_package_group.adapters.model_package_group_name
}

output "adapter_bucket_prefix" {
  description = "S3 prefix where trained adapter weights are stored"
  value       = "s3://${data.tfe_outputs.ai_storage.outputs.bucket_names["adapter_weights"]}/${var.client_id}/${var.env}/"
}

output "notification_topic_arn" {
  description = "SNS topic ARN for pipeline completion notifications"
  value       = aws_sns_topic.fine_tuning_notifications.arn
}

output "sagemaker_role_arn" {
  description = "SageMaker execution role ARN"
  value       = aws_iam_role.sagemaker_exec.arn
}
```

---

## Todos

### Infrastructure
- [ ] Create `workspaces/ai-fine-tuning/` directory
- [ ] Create `workspaces/ai-fine-tuning/main.tf` — Step Functions, SNS, EventBridge
- [ ] Create `workspaces/ai-fine-tuning/iam.tf` — SageMaker role, Step Functions role, Lambda role
- [ ] Create `workspaces/ai-fine-tuning/variables.tf` — `ai_fine_tuning_config_json` variable
- [ ] Create `workspaces/ai-fine-tuning/outputs.tf`
- [ ] Create `workspaces/ai-fine-tuning/data.tf` — ai-storage, ecr, iam, secure_baseline outputs
- [ ] Create `workspaces/ai-fine-tuning/training/train.py` — LoRA training script
- [ ] Create `workspaces/ai-fine-tuning/training/requirements.txt` — transformers, peft, trl, datasets
- [ ] Create `workspaces/ai-fine-tuning/evaluation/eval.py` — perplexity evaluation script
- [ ] Create data validation Lambda function code

### Control Plane Wiring
- [ ] Add `ai-fine-tuning` to `service_working_dirs` map
- [ ] Add dependency: requires `ai-storage`, `ecr`, `iam`, `secure-baseline`
- [ ] Add `ai_fine_tuning_config_json` schema validation (valid `trigger` values: `manual`, `s3_event`)

### Consumer Wiring (forge-core-ai)
- [ ] Add `LORA_ADAPTER_S3_URI` env var to ECS task definition (injected from Model Registry approved adapter)
- [ ] Add PEFT adapter loading logic to forge-core-ai startup
- [ ] Add peft + trl to forge-core-ai dependencies

### Test Client
- [ ] Add `ai-fine-tuning` to a test client services array (post-MVP)
- [ ] Apply workspace and verify Step Functions state machine created
- [ ] Upload a small JSONL training set to training-data bucket and trigger pipeline manually
- [ ] Verify training job starts in SageMaker console

---

## Verification

```bash
# 1. Confirm state machine created
aws stepfunctions list-state-machines \
  --query "stateMachines[?contains(name, 'fine-tuning')].name"
# Expected: ["test-client-dev-fine-tuning-pipeline"]

# 2. Confirm Model Package Group created
aws sagemaker list-model-package-groups \
  --query "ModelPackageGroupSummaryList[?ModelPackageGroupName=='test-client-dev-lora-adapters'].ModelPackageGroupName"
# Expected: ["test-client-dev-lora-adapters"]

# 3. Trigger a manual pipeline run (requires training data in S3 first)
aws stepfunctions start-execution \
  --state-machine-arn $(terraform output -raw pipeline_arn) \
  --input '{
    "input": {
      "s3_training_data_uri": "s3://test-client-dev-ai-training-data/runs/test-001/",
      "dataset_name": "test-domain-001",
      "executionId": "test-001"
    }
  }'
# Expected: executionArn returned

# 4. Watch execution progress
aws stepfunctions get-execution-history \
  --execution-arn <executionArn> \
  --query "events[-5:].{type:type,timestamp:timestamp}"
# Expected: progression through ValidateData → StartTraining → ...

# 5. After training completes — check adapter in S3
aws s3 ls s3://test-client-dev-ai-adapter-weights/test-client/dev/
# Expected: adapter checkpoint files listed
```

**Gate (post-MVP):** State machine created; manual execution reaches `StartTraining` step;
adapter weights appear in S3 after training completes; Model Package Group shows new version.

---

## Cost Notes

| Resource | Cost |
|---|---|
| SageMaker training — ml.g4dn.xlarge Spot | ~$0.53/hr Spot (~$0.75/hr on-demand) |
| Typical training run (2–4 hrs) | ~$1.06–$2.12 on Spot |
| S3 storage (adapter weights ~50MB each) | ~$0.001/adapter/month |
| Step Functions (standard workflow) | $0.025 per 1K state transitions |
| SNS notification | ~$0 |
| SageMaker Model Registry | $0 |
| **Estimated cost per fine-tuning run** | **~$2–10 on Spot** |

Spot interruptions are handled automatically by SageMaker — the job restarts from the
last checkpoint stored in S3. On-demand fallback can be configured if Spot is unavailable.

**When to run training:** On-demand (manual trigger) initially. Move to scheduled weekly
retraining once a client's training data pipeline is mature and eval metrics are stable.
