// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {Test, console} from "forge-std/Test.sol";

/// @dev MV-04 (`local_deployment/specs/mv_04_default_tier_liability_bounded.spec`):
/// tier(0).liabilityShares <= tier(0).shareLimit
interface IOperatorGrid {
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

    struct TierParams {
        uint256 shareLimit;
        uint256 reserveRatioBP;
        uint256 forcedRebalanceThresholdBP;
        uint256 infraFeeBP;
        uint256 liquidityFeeBP;
        uint256 reservationFeeBP;
    }

    function tier(uint256 tierId) external view returns (Tier memory);
    function alterTiers(uint256[] calldata tierIds, TierParams[] calldata tierParams) external;
}

interface IAccessControl {
    function grantRole(bytes32 role, address account) external;
}

/// @dev Reproduces Orca trace: OperatorGrid(0xc696...).alterTiers from 0x4ca5... with tier 0 params
///      `(100, 1981, 98, 26273, 53413, 47334)`, then evaluates MV-04.
///
///      At fork block 24779995, `ALTER_SENDER` does not hold `REGISTRY_ROLE`; `OPERATOR_GRID_ADMIN`
///      grants it in `setUp` so the same `msg.sender` can execute the tx (mirrors the Dashboard pattern
///      in `WithdrawableValueBound.t.sol`).
contract DefaultTierLiabilityBounded is Test {
    address constant OPERATOR_GRID = 0xC69685E89Cefc327b43B7234AC646451B27c544d;
    /// @dev Intended trace sender
    address constant ALTER_SENDER = 0x4ca5B264B82224c963a939a6a0A99C14C944Dca9;
    /// @dev Sole `DEFAULT_ADMIN_ROLE` holder on OperatorGrid at fork block 24779995
    address constant OPERATOR_GRID_ADMIN = 0x3e40D73EB977Dc6a537aF587D48316feE66E9C8c;

    bytes32 constant REGISTRY_ROLE = keccak256("vaults.OperatorsGrid.Registry");

    IOperatorGrid operatorGrid = IOperatorGrid(OPERATOR_GRID);
    IAccessControl operatorGridAccess = IAccessControl(OPERATOR_GRID);

    function setUp() public {
        vm.createSelectFork("mainnet", 24779995);
        vm.startPrank(OPERATOR_GRID_ADMIN);
        operatorGridAccess.grantRole(REGISTRY_ROLE, ALTER_SENDER);
        vm.stopPrank();
    }

    function test_mv04_defaultTierLiabilityBounded_afterAlterTiers() public {
        uint256[] memory tierIds = new uint256[](1);
        tierIds[0] = 0;

        IOperatorGrid.TierParams[] memory params = new IOperatorGrid.TierParams[](1);
        params[0] = IOperatorGrid.TierParams({
            shareLimit: 100,
            reserveRatioBP: 1981,
            forcedRebalanceThresholdBP: 98,
            infraFeeBP: 26273,
            liquidityFeeBP: 53413,
            reservationFeeBP: 47334
        });

        vm.prank(ALTER_SENDER);
        operatorGrid.alterTiers(tierIds, params);

        IOperatorGrid.Tier memory t = operatorGrid.tier(0);
        uint256 liability = uint256(t.liabilityShares);
        uint256 limit = uint256(t.shareLimit);
        bool specHolds = liability <= limit;

        if (!specHolds) {
            console.log("=== MV-04 violated after alterTiers(tier 0) ===");
            console.log("tierId:            0");
            console.log("operator:          ", t.operator);
            console.log("shareLimit:        ", limit);
            console.log("liabilityShares:   ", liability);
            console.log("excess liability:  ", liability - limit);
            console.log("reserveRatioBP:    ", t.reserveRatioBP);
            console.log("forcedRebalanceBP: ", t.forcedRebalanceThresholdBP);
        }

        assertFalse(specHolds, "MV-04: expected tier(0).liabilityShares > tier(0).shareLimit after this alterTiers");
    }
}
