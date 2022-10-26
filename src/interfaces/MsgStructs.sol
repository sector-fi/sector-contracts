// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.16;

struct Message {
	uint256 value;
	address sender;
	address client; // In case of emergency withdraw, this is the address to send the funds to
	uint16 chainId;
}

struct Vault {
	uint16 postmanId;
	bool allowed;
}

struct VaultAddr {
	address addr;
	uint16 chainId;
}

struct Request {
	address vaultAddr;
	uint16 vaultChainId;
	uint256 amount;
    uint256 bridgeFee;
	address allowanceTarget;
	address registry;
	bytes txData;
}

enum MessageType {
	NONE,
	DEPOSIT,
	WITHDRAW,
	EMERGENCYWITHDRAW,
	HARVEST
}
