# API docs checks

The `@API`, `@returns` and `@model` comments in controllers generate the OpenAPI
spec and the clients built from it. These checks keep those comments in line with
what the API returns. Each one fails only on findings that
`lib/api_docs_audit/exceptions.yml` doesn't list.

| Check | Runs | Needs a database | Catches |
|---|---|---|---|
| `Lint/ApiDocs` cop | `script/rlint` and the pre-commit hook, on changed controllers; CI on every controller | No | An `@API` action with no `@returns`, and `@model` JSON that doesn't parse |
| `script/api_docs_lint` | CI, and the pre-commit hook when enabled | No | Docs that a change makes disagree with the traced code |
| Response check | API specs, when `API_DOCS_CHECK` is set | Yes | Fields, types and nulls a spec response has but the docs don't |
| `script/api_docs_audit` | Manually | Recorded responses | All of the above, across every action |

## The cop

`Lint/ApiDocs` lives in `gems/rubocop-canvas`. It reads comments the way the
generator does, so an action documented only by an example response of the form
`{ "widgets": [Widget] }` counts as documented.

```sh
bin/rubocop --only Lint/ApiDocs app/controllers/widgets_controller.rb
```

## The lint

`script/api_docs_lint` traces the code of every action a change can affect: actions
in changed controllers, and actions whose responses come from a changed helper in
`lib/api/v1`, a serializer or a model definition. It compares those traces with the
docs, and with the same traces at the base ref, so it reports only what the change
introduces.

```sh
script/api_docs_lint                      # uncommitted changes, against HEAD
script/api_docs_lint --base origin/master # a branch, against where it's going
```

The pre-commit hook runs it when `CANVAS_API_DOCS_LINT=1` is set and a staged file
is under `app/controllers`, `app/serializers`, `lib/api`, `lib/api_docs_audit` or
`lib/schemas/docs`. It takes about a minute, so it's off by default. Install the
hook with `script/install_hooks`.

The `API Docs` GitHub Actions workflow runs the lint and the cop on pull requests
that touch those paths.

## The response check

With `API_DOCS_CHECK` set, every successful response an API spec gets through
`raw_api_call` is compared with the action's documentation. An undocumented field,
a wrong type, an undocumented null or a wrong container fails the example, naming
the action and the field.

```sh
API_DOCS_CHECK=1 bin/rspec spec/apis/v1/conversations_api_spec.rb
```

A single response can't show that a documented field is missing, so that's left to
the full audit. Responses requested with string ids aren't checked.

## The full audit

The full audit needs responses recorded from the whole spec suite, about 3.2 hours
on one process, so it runs manually.

1. Record spec responses. Records hold key names and type names only.

   ```sh
   API_RESPONSE_RECORD=1 bin/rspec spec/apis spec/controllers
   ```

2. Optionally, add GET probes from a seeded instance. The python client's contract
   test writes `probes-<role>.jsonl` files; copy them to
   `tmp/api_docs_audit/evidence/probes/`, and dump the route map they need:

   ```sh
   bin/rails runner 'ApiDocsAudit::Routes.dump("tmp/api_docs_audit/routes.json")'
   ```

3. Run the audit:

   ```sh
   script/api_docs_audit --structure tmp/api_docs_audit/structure.sql
   ```

`--structure` takes a schema-only dump, such as
`pg_dump --schema-only --no-owner canvas_development`, for column types. The audit
writes `tmp/api_docs_audit/findings.json` and exits non-zero when a finding isn't
in the exceptions file. It also lists entries that no longer match any finding, so
the file can shrink.

## The exceptions file

Every entry needs a reason:

- `internal`: the field or response is internal and stays undocumented.
- `unverifiable`: no response shows it, only the code or the docs.
- `notation`: the doc notation can't express it, such as a nullable model reference
  or a response with no body.
- `needs_description`: a field added from responses that still needs a description.
  These entries are a to-do list and never cover a finding.

An entry matches a finding when every key it gives, other than `reason`, equals the
finding's value:

```yaml
- kind: new_field
  model: Widget
  field: secret
  reason: internal
```

Any check that loads a file with an entry missing a valid reason fails and names
that entry.
