// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "src/libraries/Structs.sol";
import "src/libraries/Constants.sol";
import "src/interfaces/IEventFactory.sol";
import "src/core/Event.sol"; // Changed from IEvent to Event for actual implementation
import "src/core/EventDeployer.sol";

// Custom errors to reduce bytecode size
error InvalidAddress();
error EventDateMustBeInFuture();

contract EventFactory is IEventFactory, Ownable {
    // State variables
    address[] public events;
    address public idrxToken;
    address public platformFeeReceiver;
    EventDeployer public deployer;
    
    // Constructor
    constructor(address _idrxToken) {
        if(_idrxToken == address(0)) revert InvalidAddress();
        idrxToken = _idrxToken;
        platformFeeReceiver = msg.sender;
        deployer = new EventDeployer();
    }
    
    // Create a new event - anyone can call this
    function createEvent(
        string calldata _name,
        string calldata _description,
        uint256 _date,
        string calldata _venue,
        string calldata _ipfsMetadata
    ) external override returns (address) {
        if(_date <= block.timestamp) revert EventDateMustBeInFuture();
        
        // Use the deployer contract to create event and ticket
        (address eventAddress,) = deployer.deployEventAndTicket(
            msg.sender,
            _name,
            _description,
            _date,
            _venue,
            _ipfsMetadata,
            idrxToken,
            platformFeeReceiver
        );
        
        // Add to events list
        events.push(eventAddress);
        
        emit EventCreated(events.length - 1, eventAddress);
        
        return eventAddress;
    }
    
    // Get all events
    function getEvents() external view override returns (address[] memory) {
        return events;
    }
    
    // Get event details
    function getEventDetails(address eventAddress) external view override returns (Structs.EventDetails memory) {
        Event eventContract = Event(eventAddress); // Using direct cast to Event
        
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
        if(receiver == address(0)) revert InvalidAddress();
        platformFeeReceiver = receiver;
        
        emit PlatformFeeReceiverUpdated(receiver);
    }
    
    // Get platform fee percentage
    function getPlatformFeePercentage() external pure override returns (uint256) {
        return Constants.PLATFORM_FEE_PERCENTAGE;
    }
    
    // Update IDRX token address
    function updateIDRXToken(address _newToken) external onlyOwner {
        if(_newToken == address(0)) revert InvalidAddress();
        idrxToken = _newToken;
        
        emit IDRXTokenUpdated(_newToken);
    }
    
    // Events
    event EventCreated(uint256 indexed eventId, address indexed eventContract);
    event PlatformFeeReceiverUpdated(address indexed receiver);
    event IDRXTokenUpdated(address indexed newToken);
}