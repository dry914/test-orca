# Property: forceRebalance should not revert when the vault has available balance
# and outstanding health shortfall (obligations). If a vault is unhealthy and has
# ETH to rebalance with, the protocol must allow forced rebalancing to succeed.
#
# Derived from: fuzz_pr_1570/test/0.8.25/invariant-fuzzing/StakingVaultsFuzzing.t.sol
#   function invariant_03_forceRebalance_should_not_revert_when_has_available_balance_and_obligations()

vars: VaultHub vh
spec: []!reverted(vh.forceRebalance(vault),
    vh.healthShortfallShares(vault) > 0 && balance(vault) > 0
)
