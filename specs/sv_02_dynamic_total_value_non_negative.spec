# Property: Dynamic total value (including inOutDelta adjustments) should never underflow.
# The original invariant checks that the signed computation
#   int256(record.report.totalValue) + int256(record.inOutDelta.currentValue()) - int256(record.report.inOutDelta)
# remains >= 0.
#
# Derived from: fuzz_pr_1570/test/0.8.25/invariant-fuzzing/StakingVaultsFuzzing.t.sol
#   function invariant_02_dynamic_totalValue_should_not_underflow()

vars: VaultHub vh, StakingVault sv
inv: vh.vaultRecord(address(sv))[0][0] + vh.vaultRecord(address(sv))[3][0][0] >= vh.vaultRecord(address(sv))[0][1]
