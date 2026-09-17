# rebuild the test system

problem: the test suite, runner, optional native discovery gate, and ci workflow
were deliberately removed. the replacement belongs to the next pr.

impact: there is no automated regression, syntax, schema, or lint workflow.
runtime validation and apply postconditions remain, but cannot substitute for
regression checks before deployment.

evidence: the retired suite mixed behavior checks with source-string assertions
and extensive command fakes. its runner executed suites serially; service failure
cases exercised production polling deadlines. runtime was not benchmarked for
this deletion. committed tests remain available in git history.

resolution: the next pr defines the important observable invariants, chooses
checks proportional to their failure costs, sets and measures a runtime budget,
and documents a working verification command and ci policy. review lost coverage
for repeat-apply idempotence, failed-upgrade rollback and credential preservation,
bootstrap ingress cleanup, and explicit service restart authorization. remove
this issue when the replacement is verified and documented. include the new
apply/upgrade boundary and unchanged skid cache reuse in the replacement contract.
