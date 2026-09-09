// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC8183} from "../contracts/ERC8183.sol";

/// @notice Broadcasts an ERC1967 proxy pointing at ERC8183.
/// @dev Set TREASURY and ADMIN. The broadcast signer pays gas and does not need to be ADMIN
///      unless PAYMENT_TOKEN is set (allowlist requires ADMIN_ROLE).
contract Deploy is Script {
    function run() external {
        address treasury = vm.envAddress("TREASURY");
        address admin = vm.envAddress("ADMIN");
        address paymentToken = vm.envOr("PAYMENT_TOKEN", address(0));

        vm.startBroadcast();

        ERC8183 impl = new ERC8183();
        bytes memory initData = abi.encodeCall(
            ERC8183.initialize,
            (treasury, admin)
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        ERC8183 core = ERC8183(address(proxy));

        if (paymentToken != address(0)) {
            core.setPaymentTokenAllowed(paymentToken, true);
        }

        vm.stopBroadcast();

        console.log("chainId", block.chainid);
        console.log("implementation", address(impl));
        console.log("proxy", address(proxy));
        console.log("treasury", treasury);
        console.log("admin", admin);
        if (paymentToken != address(0)) {
            console.log("paymentToken", paymentToken);
        }
    }
}
