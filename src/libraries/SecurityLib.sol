// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ECDSA} from "lib/openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";

library SecurityLib {
    using ECDSA for bytes32;

    function recoverSigner(bytes32 messageHash, bytes memory signature) internal pure returns (address) {
        return messageHash.toEthSignedMessageHash().recover(signature);
    }
    
    function validateChallenge(bytes32 challenge, uint256 timestamp, uint256 validityWindow) internal view returns (bool) {
        // Validasi timestamp - pastikan tidak terlalu lama atau di masa depan
        if (timestamp > block.timestamp) {
            return false; // Timestamp di masa depan
        }
        
        if (block.timestamp - timestamp > validityWindow) {
            return false; // Challenge sudah kedaluwarsa
        }
        
        return true;
    }
}