pragma solidity ^0.8.0;

import "./Exchange.sol";

contract Factory{
    mapping(address => address) public tokenToExchange; 

    function getExchange(address _tokenAddress)public view returns(address){
        return tokenToExchange[_tokenAddress];
    }

    function createExchange(address _tokenAddress) public returns(address){
        require(_tokenAddress != address(0), "invalid tokenAddress");
        
        require(tokenToExchange[_tokenAddress] == address(0), "echange already exists");

        Exchange exchange = new Exchange(_tokenAddress);
        tokenToExchange[_tokenAddress] = address(exchange);
        return address(exchange);
    }
}