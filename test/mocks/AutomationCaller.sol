// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract AutomationCaller {
    function callTarget(address target, bytes calldata data) external returns (bool success) {
        (success,) = target.call(data);
    }
}
