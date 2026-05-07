# Property: The applied (oracle-processed) total value should not exceed the reported
# total value. In the fuzz test, the handler tracks reportedTotalValue (vault ETH balance
# at report time) and appliedTotalValue (what the oracle stores after sanity checks and
# quarantine). The invariant ensures oracle processing never inflates the value.
##
# Derived from: fuzz_pr_1570/test/0.8.25/invariant-fuzzing/StakingVaultsFuzzing.t.sol
#   function invariant_05_applied_tv_should_not_be_greater_than_reported_tv()

vars: VaultHub vh, StakingVault sv
inv: vh.totalValue(address(sv)) <= balance(address(sv))
