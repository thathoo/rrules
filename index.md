## Expand RRULEs via API

Get individual occurrences of an RRULE directly via API. The API backend is deployed on AWS Lambda behind API Gateway, and relies on the [ruby-rrule](https://github.com/square/ruby-rrule) gem.

The production URL is an AWS-managed API Gateway URL:

```text
https://<api-id>.execute-api.<region>.amazonaws.com/prod
```

```sh
curl -X POST https://<api-id>.execute-api.<region>.amazonaws.com/prod/rrule_expand \
  -H 'Content-Type: application/json' \
  -d '{"rrule":"FREQ=DAILY;COUNT=3","start_time":"2019-03-05 00:46:42 -0800","end_time":"2019-06-05 00:46:42 -0800"}'
```

Response:

```json
{
  "message": "ok",
  "occurrences": [
    "2019-03-05T08:46:42Z",
    "2019-03-06T08:46:42Z",
    "2019-03-07T08:46:42Z"
  ]
}
```

### Parameters

param | Details | Required
------------ | ------------- | -------------
rrule | Pass in an RRULE that conforms to [RFC 5545](https://tools.ietf.org/html/rfc5545) | Yes
start_time | Pass in a start_time that can be parsed by Ruby's `Time.parse` [method](https://ruby-doc.org/stdlib-2.1.1/libdoc/time/rdoc/Time.html#method-c-parse) | Yes
end_time | Pass in an end_time that can be parsed by Ruby's `Time.parse` [method](https://ruby-doc.org/stdlib-2.1.1/libdoc/time/rdoc/Time.html#method-c-parse) | No (defaults to one year from request time)
time_zone | Example: `America/Los_Angeles` | No (defaults to `UTC`)

You can pass parameters in a JSON request body, a form-encoded request body, or the query string.

If the same parameter is present in both the query string and request body, the request body value wins.

### Response Contract

Responses return an `occurrences` array of ISO 8601 UTC timestamps. Earlier versions of this API returned a comma-joined `rrules` string; clients should migrate to `occurrences`.

### Errors

Error responses use a structured JSON body:

```json
{
  "error": "missing_parameter",
  "message": "Missing required parameter(s): rrule"
}
```

Supported requests must stay within a 100 year boundary from the request time.

### Development

Use Ruby 3.0 or newer.

```sh
bundle install
bundle exec rspec
```

### Deployment

This project deploys to AWS Lambda and API Gateway HTTP API without a custom domain. The generated endpoint uses API Gateway's default `execute-api` hostname.

Requirements:

- AWS CLI v2
- Docker
- `zip`
- AWS credentials with access to Lambda, API Gateway, CloudFormation, IAM, S3, and CloudWatch Logs

Deploy:

```sh
export AWS_REGION=us-west-2
export ARTIFACT_BUCKET=rrules-api-artifacts-us-west-2
scripts/deploy_aws.sh
```

The deploy script prints the `ApiBaseUrl`, `RRuleExpandUrl`, and `HealthUrl` CloudFormation outputs. Use `RRuleExpandUrl` as the public API endpoint.

### Support or Contact

Having trouble with the API? Please create an issue and I will do my best to be responsive. If you plan to hit the API with more than a couple thousand requests a day, please let me know first.
