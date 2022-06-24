// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Context.sol";

contract RandomierPool is Context {
    address public owner;
    uint256 id;
    uint256 immutable totalCount;
    uint256 public alreadyPopCount;
    uint256 private salt;

    mapping(uint256 => uint256) pool;

    constructor(uint256 id_, uint256 totalCount_) public {
        owner = _msgSender();
        id = id_;
        totalCount = totalCount_;
        salt = uint256(
            keccak256(
                abi.encodePacked(
                    block.timestamp,
                    block.difficulty,
                    block.number,
                    totalCount_
                )
            )
        );
    }

    // generate a random number
    function generateRandom() public view returns (uint256) {
        return
            uint256(
                keccak256(
                    abi.encodePacked(
                        block.timestamp,
                        block.difficulty,
                        block.number,
                        salt
                    )
                )
            );
    }

    // get number for prize from pool
    function getNumber() public returns (uint256) {
        require(owner == _msgSender(), "msg.sender is not owner");
        require(alreadyPopCount < totalCount, "pool has drawed out");
        uint256 randomIndex = (generateRandom() %
            (totalCount - alreadyPopCount)) + alreadyPopCount;
        uint256 randomNumber = _indexNumberMap(randomIndex);
        uint256 currentNumber = _indexNumberMap(alreadyPopCount);
        pool[randomIndex] = currentNumber;
        pool[alreadyPopCount] = randomNumber;
        alreadyPopCount++;
        return randomNumber;
    }

    function _indexNumberMap(uint256 index_) private view returns (uint256) {
        if (pool[index_] == 0) {
            return index_ + 1;
        } else {
            return pool[index_];
        }
    }
}
