// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {Test, console} from "forge-std/Test.sol";

interface IOperatorGrid {
    struct Group {
        address operator;
        uint96 shareLimit;
        uint96 liabilityShares;
        uint256[] tierIds;
    }

    struct Tier {
        address operator;
        uint96 shareLimit;
        uint96 liabilityShares;
        uint16 reserveRatioBP;
        uint16 forcedRebalanceThresholdBP;
        uint16 infraFeeBP;
        uint16 liquidityFeeBP;
        uint16 reservationFeeBP;
    }

    function tier(uint256 tierId) external view returns (Tier memory);
    function group(address nodeOperator) external view returns (Group memory);
}

contract TierLiabilityWithinGroupLimit is Test {
    address constant OPERATOR_GRID = 0xC69685E89Cefc327b43B7234AC646451B27c544d;

    IOperatorGrid og = IOperatorGrid(OPERATOR_GRID);

    function setUp() public {
        vm.createSelectFork("mainnet", 24779995);
    }

    function test_tierLiabilityWithinGroupLimit() external view {
        console.log("=== MV-02: Tier Liability Within Group Limit ===");
        console.log("Invariant: tier.liabilityShares <= group(tier.operator).shareLimit");
        console.log("");

        uint256 violations = 0;

        for (uint256 tierId = 0; tierId <= 10; tierId++) {
            console.log("--- Tier", tierId, "---");

            // Attempt to read the tier; if it doesn't exist the call reverts
            try og.tier(tierId) returns (IOperatorGrid.Tier memory t) {
                console.log("  operator:         ", t.operator);
                console.log("  shareLimit:       ", uint256(t.shareLimit));
                console.log("  liabilityShares:  ", uint256(t.liabilityShares));

                IOperatorGrid.Group memory g = og.group(t.operator);
                console.log("  group.operator:   ", g.operator);
                console.log("  group.shareLimit: ", uint256(g.shareLimit));
                console.log("  group.liabShares: ", uint256(g.liabilityShares));
                console.log("  group.tierCount:  ", g.tierIds.length);

                bool holds = t.liabilityShares <= g.shareLimit;
                if (holds) {
                    console.log("  INVARIANT:         HOLDS");
                } else {
                    console.log("  INVARIANT:         VIOLATED");
                    violations++;
                }
            } catch {
                console.log("  (tier does not exist, skipping)");
            }

            console.log("");
        }

        console.log("=== Summary ===");
        console.log("Tiers checked: 0 through 10");
        console.log("Violations:   ", violations);

        assertEq(violations, 0, "MV-02: tier liabilityShares exceeds parent group shareLimit");
    }
}
