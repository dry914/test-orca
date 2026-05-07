// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {Test, console} from "forge-std/Test.sol";

/// @dev Mirrors `VaultHub` custom errors for decoding revert payloads.
error VaultReportStale(address vault);
error ForcedValidatorExitNotAllowed();

interface IAccessControlEnumerable {
    function DEFAULT_ADMIN_ROLE() external view returns (bytes32);
    function getRoleMember(bytes32 role, uint256 index) external view returns (address);
    function hasRole(bytes32 role, address account) external view returns (bool);
    function grantRole(bytes32 role, address account) external;
}

interface IVaultHub is IAccessControlEnumerable {
    function REDEMPTION_MASTER_ROLE() external view returns (bytes32);
    function VALIDATOR_EXIT_ROLE() external view returns (bytes32);

    function setLiabilitySharesTarget(address _vault, uint256 _liabilitySharesTarget) external;

    function forceValidatorExit(address _vault, bytes calldata _pubkeys, address _refundRecipient) external payable;
}

/// @dev Replays the sv_04 counterexample from `call_metrics.json` on the pinned mainnet fork (block 24779995).
///      On live mainnet `0xC283...` is not `REDEMPTION_MASTER` and `0x4508...` may lack `VALIDATOR_EXIT_ROLE`,
///      so we grant those roles from the real VaultHub admin (same approach as `script/OrCa.s.sol` role setup).
///      Timestamps match the OrCa trace: first call at `1774989334`, second after `+604800` seconds.
contract ForceValidatorExitRevert is Test {
    address constant VAULT_HUB = 0x1d201BE093d847f6446530Efb0E8Fb426d176709;
    address constant VAULT = 0x62e0D92cf7B8752b5292B9BCbbacE4cFa1633428;
    address constant REDEMPTION_SENDER = 0xC28317c7F9e4aEE13931a61D4e36e93d9481B298;
    address constant EXIT_SENDER = 0x4508B5cf2B72101e58cd029bC9004C81a5064ca9;
    address constant REFUND_RECIPIENT = 0x4ca5B264B82224c963a939a6a0A99C14C944Dca9;

    /// @dev Counterexample value `72057594037927935` (`2^56 - 1`, shown as ~7.20576e16 in tooling).
    uint256 constant LIABILITY_SHARES_TARGET = 72057594037927935;

    uint256 constant WARP_AT_FIRST_CALL = 1774989334;
    uint256 constant WARP_AT_SECOND_CALL = 1775594134;

    bytes constant PUBKEYS =
        hex"5d4ac5ce6dfa5bfffb7c14fef286ffcfb78e9bbb76be8a44c11588b67a01c888d1571f4f7d81e886b08705e9e4d8941c";

    IVaultHub vaultHub = IVaultHub(VAULT_HUB);

    function setUp() public {
        vm.createSelectFork("mainnet", 24779995);

        address admin = vaultHub.getRoleMember(vaultHub.DEFAULT_ADMIN_ROLE(), 0);
        vm.startPrank(admin);
        bytes32 redemptionRole = vaultHub.REDEMPTION_MASTER_ROLE();
        if (!vaultHub.hasRole(redemptionRole, REDEMPTION_SENDER)) {
            vaultHub.grantRole(redemptionRole, REDEMPTION_SENDER);
        }
        bytes32 exitRole = vaultHub.VALIDATOR_EXIT_ROLE();
        if (!vaultHub.hasRole(exitRole, EXIT_SENDER)) {
            vaultHub.grantRole(exitRole, EXIT_SENDER);
        }
        vm.stopPrank();
    }

    function test_forceValidatorExit_reverts_after_setLiabilitySharesTarget() public {
        vm.warp(WARP_AT_FIRST_CALL);

        vm.prank(REDEMPTION_SENDER);
        vaultHub.setLiabilitySharesTarget(VAULT, LIABILITY_SHARES_TARGET);

        vm.warp(WARP_AT_SECOND_CALL);

        vm.deal(EXIT_SENDER, 1 ether);
        vm.prank(EXIT_SENDER);
        (bool ok, bytes memory ret) = address(vaultHub).call{value: 1}(
            abi.encodeCall(IVaultHub.forceValidatorExit, (VAULT, PUBKEYS, REFUND_RECIPIENT))
        );

        assertFalse(ok, "forceValidatorExit should revert after this sequence");

        console.log("--- forceValidatorExit revert ---");
        if (ret.length >= 4) {
            bytes4 sel = bytes4(ret);
            console.logBytes4(sel);
            if (sel == VaultReportStale.selector && ret.length >= 4 + 32) {
                address v = abi.decode(_slice(ret, 4, ret.length - 4), (address));
                console.log("decoded: VaultReportStale(vault)", v);
            } else if (sel == ForcedValidatorExitNotAllowed.selector) {
                console.log("decoded: ForcedValidatorExitNotAllowed()");
            }
        }
        console.log("raw revert data:");
        console.logBytes(ret);
    }

    function _slice(bytes memory data, uint256 start, uint256 len) private pure returns (bytes memory out) {
        out = new bytes(len);
        for (uint256 i = 0; i < len; i++) {
            out[i] = data[start + i];
        }
    }
}
