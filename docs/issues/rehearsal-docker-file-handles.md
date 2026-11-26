# docker file handles after rehearsal teardown

docker desktop on macbook retained read handles on two disposable huawei
rehearsal worktrees after their containers exited. the rehearsal cleanup
guard left the worktrees registered. the `huawei-plasma-13f14dd-01` and `-02`
receipts under the local evidence directory identify the exact paths.

stream the fixture files into the container to avoid binding the checkout.
clean the two retained paths once docker releases its handles and the
[recovery checks](../desktop.md#development-placement) pass. wait for active
containers to finish before restarting docker if it still holds the paths.
