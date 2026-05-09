# Pillar 1 — Liveness under fairness.
#
# Under a fair oracle (oracleRunner.report keeps firing), every requested
# withdrawal must eventually become claimable. Without `fair:` the property
# trivially fails because the oracle would never report. With `fair:` Orca
# hunts for any counterexample where claim is permanently blocked despite
# reports arriving.
#
# `oracleRunner.report` is our wrapper installed at the AccountingOracle
# proxy address (anvil_setCode in script/OrCa.s.sol); each successful call
# drives Accounting.handleOracleReport → Lido._processRewardsAndWithdrawals
# → WithdrawalQueue.finalize on the live forked state.
#
# Foundry has no analogue: invariant mode is bounded reachability and offers
# no semantic notion of "eventually". Closest approximation would be a
# bounded `assertTrue(claim_reached_within_N_steps)`, which is a different
# property with a different guarantee.

vars: OracleReportRunner oracleRunner, WithdrawalQueueERC721 wq

fair: [] <> finished(oracleRunner.report)

spec: [] (finished(wq.requestWithdrawals)
    ==> <> finished(wq.claimWithdrawal))
