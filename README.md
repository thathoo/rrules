## Expand RRULEs via API

Get individual occurrences of any RRULE directly via API (api.rrules.com). The API backend is deployed on AWS Lambda, and relies on the [ruby-rrule](https://github.com/square/ruby-rrule) gem. Try it yourself, see example below!

```markdown
curl -X POST https://api.rrules.com/rrule_expand -d '{"rrule":"FREQ=DAILY;COUNT=3", "start_time":"2019-03-05 00:46:42 -0800", "end_time":"2019-06-05 00:46:42 -0800"}'
```

### Query Parameters 

param | Details | Required
------------ | ------------- | -------------
rrule | Pass in an RRULE that conforms to [RFC 5545](https://tools.ietf.org/html/rfc5545) | Yes
start_time | Pass in a start_time that can be parsed by Ruby's `Time.parse` [method](https://ruby-doc.org/stdlib-2.1.1/libdoc/time/rdoc/Time.html#method-c-parse) | Yes
end_time | Pass in an end_time that can be parsed by Ruby's `Time.parse` [method](https://ruby-doc.org/stdlib-2.1.1/libdoc/time/rdoc/Time.html#method-c-parse) | No (defaults to `1.year.from_now`)
time_zone | Example: `America/Los_Angeles` | No (defaults to `UTC`)

### Support or Contact

Having trouble with the API? Please create an issue and I will do my best to be responsive, quickly. If you plan to hit the API with more than a couple thousand requests a day, please let me know first.
