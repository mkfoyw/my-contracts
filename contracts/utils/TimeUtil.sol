// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library TimeUtil {
    function currentTime() internal view returns (uint256) {
        unchecked {
            return block.timestamp;
        }
    }
}
