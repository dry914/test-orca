# Property: forceValidatorExit should not revert when the vault has an obligations
# shortfall. When a vault's total value is insufficient to cover its obligations,
# the protocol must allow forced validator exits to proceed.
#
# Derived from: fuzz_pr_1570/test/0.8.25/invariant-fuzzing/StakingVaultsFuzzing.t.sol
#   function invariant_04_forceValidatorExit_should_not_revert_when_has_obligations_shortfall()

vars: VaultHub vh
spec: []!reverted(vh.forceValidatorExit(vault, pubkeys, refund),
    vh.obligationsShortfallValue(vault) > 0
)
