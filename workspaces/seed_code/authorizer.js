exports.handler = async (event) => {
  const resource = event?.methodArn || "*";

  return {
    principalId: "seed-initializer",
    policyDocument: {
      Version: "2012-10-17",
      Statement: [
        {
          Action: "execute-api:Invoke",
          Effect: "Allow",
          Resource: resource,
        },
      ],
    },
    context: {
      authorized: "true",
      source: "seed",
    },
  };
};
