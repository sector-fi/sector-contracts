// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.16;

struct Message {
    uint256 value;
    address sender;
    address client;
    uint16 chainId;
}

enum messageType {
    NONE,
    DEPOSIT,
    WITHDRAW,
    EMERGENCYWITHDRAW,
    REQUESTHARVEST,
    HARVEST
}