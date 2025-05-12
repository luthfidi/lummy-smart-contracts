// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "src/libraries/Structs.sol";
import "src/libraries/Constants.sol";
import "src/interfaces/IEventFactory.sol";
import "src/interfaces/IEvent.sol";
import "src/core/Event.sol";
import "src/core/TicketNFT.sol";

contract EventFactory is IEventFactory, Ownable {
    // State variables
    address[] public events;
    address public idrxToken;
    address public platformFeeReceiver;
    
    // Constructor
    constructor(address _idrxToken) {
        require(_idrxToken != address(0), "Invalid IDRX token address");
        idrxToken = _idrxToken;
        platformFeeReceiver = msg.sender; // Default is deployer
        _transferOwnership(msg.sender); // Set the owner manually
    }
    
    // Create a new event
    function createEvent(
        string memory _name,
        string memory _description,
        uint256 _date,
        string memory _venue,
        string memory _ipfsMetadata
    ) external override returns (address) {
        require(_date > block.timestamp, "Event date must be in the future");
        
        // Deploy new Event contract
        Event newEvent = new Event();
        
        // Initialize event
        newEvent.initialize(
            msg.sender,
            _name,
            _description,
            _date,
            _venue,
            _ipfsMetadata
        );
        
        // Deploy new TicketNFT contract
        TicketNFT newTicketNFT = new TicketNFT();
        
        // Initialize TicketNFT
        string memory symbol = "TIX";
        newTicketNFT.initialize(_name, symbol, address(newEvent));
        
        // Set TicketNFT pada Event
        newEvent.setTicketNFT(address(newTicketNFT), idrxToken, platformFeeReceiver);
        
        // Add to events list
        events.push(address(newEvent));
        
        // Emit event
        emit EventCreated(events.length - 1, address(newEvent), _name);
        
        return address(newEvent);
    }
    
    // Get all events
    function getEvents() external view override returns (address[] memory) {
        return events;
    }
    
    // Get event details
    function getEventDetails(address eventAddress) external view override returns (Structs.EventDetails memory) {
        Event eventContract = Event(eventAddress);
        
        return Structs.EventDetails({
            name: eventContract.name(),
            description: eventContract.description(),
            date: eventContract.date(),
            venue: eventContract.venue(),
            ipfsMetadata: eventContract.ipfsMetadata(),
            organizer: eventContract.organizer()
        });
    }
    
    // Set platform fee receiver
    function setPlatformFeeReceiver(address receiver) external override onlyOwner {
        require(receiver != address(0), "Invalid fee receiver address");
        platformFeeReceiver = receiver;
        
        emit PlatformFeeReceiverUpdated(receiver);
    }
    
    // Get platform fee percentage
    function getPlatformFeePercentage() external pure override returns (uint256) {
        return Constants.PLATFORM_FEE_PERCENTAGE;
    }
    
    // Update IDRX token address (in case token is upgraded)
    function updateIDRXToken(address _newToken) external onlyOwner {
        require(_newToken != address(0), "Invalid token address");
        idrxToken = _newToken;
        
        emit IDRXTokenUpdated(_newToken);
    }
    
    // Events
    event EventCreated(uint256 indexed eventId, address indexed eventContract, string name);
    event PlatformFeeReceiverUpdated(address indexed receiver);
    event IDRXTokenUpdated(address indexed newToken);
}