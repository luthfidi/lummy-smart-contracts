// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "src/libraries/Structs.sol";

interface ITicketNFT {
    function initialize(
        string memory _eventName,
        string memory _symbol,
        address _eventContract
    ) external;
    
    function mintTicket(
        address to,
        uint256 tierId,
        uint256 originalPrice
    ) external returns (uint256);
    
    function transferTicket(address to, uint256 tokenId) external;
    
    function generateQRChallenge(uint256 tokenId) external view returns (bytes32);
    
    function verifyTicket(
        uint256 tokenId,
        address owner,
        uint256 timestamp,
        bytes memory signature
    ) external view returns (bool);
    
    function useTicket(uint256 tokenId) external;
    
    function getTicketMetadata(uint256 tokenId) external view returns (Structs.TicketMetadata memory);
    
    function markTransferred(uint256 tokenId) external;
}