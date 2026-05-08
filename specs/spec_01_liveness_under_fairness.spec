# Pillar 1 — Liveness under fairness.
#
# Under a fair oracle (handleOracleReport keeps firing), every requested
# withdrawal must eventually become claimable. Without `fair:` the property
# trivially fails because the oracle would never report. With `fair:` Orca
# hunts for any counterexample where claim is permanently blocked despite
# reports arriving.
#
# Foundry has no analogue: invariant mode is bounded reachability and offers
# no semantic notion of "eventually". Closest approximation would be a
# bounded `assertTrue(claim_reached_within_N_steps)`, which is a different
# property with a different guarantee.

vars: Accounting accounting, WithdrawalQueueERC721 wq

fair: [] <> finished(accounting.handleOracleReport)

spec: [] (finished(wq.requestWithdrawals)
    ==> <> finished(wq.claimWithdrawal))
