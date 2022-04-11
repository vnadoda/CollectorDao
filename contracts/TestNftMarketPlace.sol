//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.8;

import "hardhat/console.sol";
import "./INftMarketPlace.sol";

contract TestNftMarketPlace is INftMarketPlace {
    function getPrice(address nftContract, uint nftId) external returns (uint price) {
        console.log("Price for NFT %s is %s", nftId, nftId);
        return nftId;
    }

    function buy(address nftContract, uint nftId) external payable returns (bool success) {
        console.log("Bought NFT %s for %s", nftId, msg.value);
        return true;
    }
}