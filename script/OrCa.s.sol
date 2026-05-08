// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {Dummy} from "../src/Dummy.sol";

interface ILidoLocator {
    function accountingOracle() external view returns (address);
    function accounting() external view returns (address);
    function lido() external view returns (address);
    function withdrawalQueue() external view returns (address);
}

/// @notice Anvil setup for the OrCa showcase (Lido v3, mainnet fork).
///         Mirrors the impersonate/fund pattern from the PR-1570 setup so that
///         `vm.broadcast(addr)` calls go through eth_sendTransaction without keys.
///         Acts: user1/user2/attacker (Anvil defaults) + oracle_addr (real
///         AccountingOracle proxy from LidoLocator).
contract DeploySetup is Script {
    address constant LIDO_LOCATOR = 0xC1d0b3DE6792Bf6b4b37EccdcC24e45978Cfd2Eb;

    address constant USER1    = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    address constant USER2    = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
    address constant ATTACKER = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC;

    /// @dev 10_000 ether in wei, hex for `anvil_setBalance`.
    string private constant _ANVIL_BALANCE_WEI_HEX = "0x21e19e0c9bab2400000";
    /// @dev 1e24 wei (~1M ETH) for user accounts.
    string private constant _ANVIL_USER_BALANCE_WEI_HEX = "0xd3c21bcecceda1000000";

    function run() external {
        address oracleAddr = ILidoLocator(LIDO_LOCATOR).accountingOracle();
        console.log("AccountingOracle (oracle_addr):", oracleAddr);

        _impersonateAndFund(oracleAddr, _ANVIL_BALANCE_WEI_HEX);
        _impersonateAndFund(USER1,    _ANVIL_USER_BALANCE_WEI_HEX);
        _impersonateAndFund(USER2,    _ANVIL_USER_BALANCE_WEI_HEX);
        _impersonateAndFund(ATTACKER, _ANVIL_USER_BALANCE_WEI_HEX);

        // Empty user runtime code so tx senders are clean EOAs.
        _clearCode(USER1);
        _clearCode(USER2);
        _clearCode(ATTACKER);

        // Make sure forge-script sees at least one deployment, otherwise it errors.
        vm.broadcast(USER1);
        Dummy d = new Dummy();
        console.log("Dummy deployed at:", address(d));
    }

    function _impersonateAndFund(address a, string memory balanceHex) private {
        string memory addrJson = string.concat('"', vm.toString(a), '"');
        vm.rpc("anvil_impersonateAccount", string.concat("[", addrJson, "]"));
        vm.rpc("anvil_setBalance", string.concat("[", addrJson, ",", '"', balanceHex, '"', "]"));
        vm.deal(a, 1_000_000 ether);
    }

    function _clearCode(address a) private {
        string memory addrJson = string.concat('"', vm.toString(a), '"');
        vm.rpc("anvil_setCode", string.concat("[", addrJson, ",", '"0x"', "]"));
    }
}
