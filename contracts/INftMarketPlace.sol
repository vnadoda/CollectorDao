//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.8;

interface INftMarketPlace {
    function getPrice(address nftContract, uint nftId) external returns (uint price);
    function buy(address nftContract, uint nftId) external payable returns (bool success);
}