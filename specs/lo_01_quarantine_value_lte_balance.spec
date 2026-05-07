# Property: LazyOracle pending quarantine value for a vault must not exceed the
# vault contract's on-chain ETH balance.
#
# quarantineValue aggregates pendingTotalValueIncrease and totalValueRemainder
# while a quarantine is active. Bounding by balance(address(sv)) ties pending
# upward TV adjustments to physical ETH on the StakingVault.
#
# If this fails on the fork (transient oracle edge cases), relax or drop after review.

vars: LazyOracle lo, StakingVault sv
inv: lo.quarantineValue(address(sv)) <= balance(address(sv))
