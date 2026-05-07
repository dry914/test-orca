# Property: Withdrawable value must be <= total value minus locked amount and
# unsettled obligation fees.
#
# Full invariant (matches Foundry):
#   withdrawableValue + locked + obligationsFees <= totalValue
# Equivalently: withdrawableValue <= max(0, totalValue - locked - obligationsFees)
#
# Tuple index for VaultHub.obligations(address):
#   [0] = sharesToBurn, [1] = feesToSettle (unsettled Lido fees in wei)
#
# Derived from: fuzz_pr_1570/test/0.8.25/invariant-fuzzing/StakingVaultsFuzzing.t.sol
#   function invariant_08_withdrawableValue_should_be_less_than_or_equal_to_totalValue_minus_locked_and_obligations()

vars: VaultHub vh, StakingVault sv
inv: 
    (vh.totalValue(address(sv)) > (vh.locked(address(sv)) + vh.obligations(address(sv))[1])) ==> 
        (
            vh.withdrawableValue(address(sv)) <= 
            vh.totalValue(address(sv)) - (vh.locked(address(sv)) + vh.obligations(address(sv))[1])
        )
    &&
    (vh.totalValue(address(sv)) <= (vh.locked(address(sv)) + vh.obligations(address(sv))[1])) ==> 
        (vh.withdrawableValue(address(sv)) <= 0)
