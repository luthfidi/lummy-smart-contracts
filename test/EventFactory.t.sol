// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "forge-std/Test.sol";
import "src/core/EventFactory.sol";
import "src/core/Event.sol";
import "src/core/TicketNFT.sol";
import "src/libraries/Constants.sol";
import "forge-std/console.sol";

// Mock IDRX token for testing
contract MockIDRX {
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    uint256 private _totalSupply;
    string private _name;
    string private _symbol;
    uint8 private _decimals;

    constructor(string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
        _decimals = 2; // IDRX has 2 decimals
    }

    function name() public view returns (string memory) {
        return _name;
    }

    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function decimals() public view returns (uint8) {
        return _decimals;
    }

    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }

    function transfer(address recipient, uint256 amount) public returns (bool) {
        _transfer(msg.sender, recipient, amount);
        return true;
    }

    function allowance(address owner, address spender) public view returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(sender, msg.sender, _allowances[sender][msg.sender] - amount);
        return true;
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    function _transfer(address sender, address recipient, uint256 amount) internal {
        require(sender != address(0), "Transfer from the zero address");
        require(recipient != address(0), "Transfer to the zero address");
        require(_balances[sender] >= amount, "Transfer amount exceeds balance");

        _balances[sender] -= amount;
        _balances[recipient] += amount;
    }

    function _mint(address account, uint256 amount) internal {
        require(account != address(0), "Mint to the zero address");

        _totalSupply += amount;
        _balances[account] += amount;
    }

    function _approve(address owner, address spender, uint256 amount) internal {
        require(owner != address(0), "Approve from the zero address");
        require(spender != address(0), "Approve to the zero address");

        _allowances[owner][spender] = amount;
    }
}

contract EventFactoryTest is Test {
    EventFactory public factory;
    MockIDRX public idrx;
    address public deployer; // Owner yang men-deploy kontrak
    address public organizer;
    address public buyer;

    function setUp() public {
        // Setup addresses
        deployer = address(this); // Test contract menjadi deployer
        organizer = makeAddr("organizer"); // Gunakan fungsi makeAddr dari Forge Test
        buyer = makeAddr("buyer");
        
        // Create mock IDRX token
        idrx = new MockIDRX("IDRX Token", "IDRX");
        
        // Deploy EventFactory dengan prank agar deployer menjadi owner
        factory = new EventFactory(address(idrx));
        
        // Mint tokens untuk testing
        idrx.mint(buyer, 10000 * 10**2); // 10,000 IDRX dengan 2 desimal
        
        // Debug - lihat owner aktual dari factory
        console.log("Factory owner:", factory.owner());
        console.log("Test contract address (deployer):", deployer);
    }

    function testCreateEvent() public {
        console.log("Starting testCreateEvent");
        console.log("Current owner:", factory.owner());
        
        // Set platform fee receiver
        factory.setPlatformFeeReceiver(deployer);
        
        // Prank as organizer
        vm.startPrank(organizer);
        
        // Create event
        uint256 eventDate = block.timestamp + 30 days;
        address eventAddress = factory.createEvent(
            "Test Event",
            "Test Description",
            eventDate,
            "Test Venue",
            "ipfs://test"
        );
        
        vm.stopPrank();
        
        // Verify event was created
        address[] memory events = factory.getEvents();
        assertEq(events.length, 1);
        assertEq(events[0], eventAddress);
        
        // Verify event details
        Structs.EventDetails memory details = factory.getEventDetails(eventAddress);
        assertEq(details.name, "Test Event");
        assertEq(details.description, "Test Description");
        assertEq(details.date, eventDate);
        assertEq(details.venue, "Test Venue");
        assertEq(details.ipfsMetadata, "ipfs://test");
        assertEq(details.organizer, organizer);
    }

    function testCreateEventAndAddTier() public {
        console.log("Starting testCreateEventAndAddTier");
        console.log("Current owner:", factory.owner());
        
        // Set platform fee receiver
        factory.setPlatformFeeReceiver(deployer);
        
        // Prank as organizer
        vm.startPrank(organizer);
        
        // Create event
        uint256 eventDate = block.timestamp + 30 days;
        address eventAddress = factory.createEvent(
            "Test Event",
            "Test Description",
            eventDate,
            "Test Venue",
            "ipfs://test"
        );
        
        // Add ticket tier
        IEvent event_ = IEvent(eventAddress);
        event_.addTicketTier(
            "General Admission",
            100 * 10**2, // 100 IDRX
            100, // 100 tickets
            4 // max 4 tickets per purchase
        );
        
        vm.stopPrank();
        
        // Verify tier was added
        (string memory name, uint256 price, uint256 available, uint256 sold, uint256 maxPerPurchase, bool active) = 
            Event(eventAddress).ticketTiers(0);
            
        assertEq(name, "General Admission");
        assertEq(price, 100 * 10**2);
        assertEq(available, 100);
        assertEq(sold, 0);
        assertEq(maxPerPurchase, 4);
        assertTrue(active);
    }

    function testBuyTicket() public {
        console.log("Starting testBuyTicket");
        console.log("Current owner:", factory.owner());
        
        // Set platform fee receiver
        factory.setPlatformFeeReceiver(deployer);
        
        // Step 1: Create event as organizer
        vm.startPrank(organizer);
        
        uint256 eventDate = block.timestamp + 30 days;
        address eventAddress = factory.createEvent(
            "Test Event",
            "Test Description",
            eventDate,
            "Test Venue",
            "ipfs://test"
        );
        
        // Add ticket tier
        IEvent event_ = IEvent(eventAddress);
        event_.addTicketTier(
            "General Admission",
            100 * 10**2, // 100 IDRX
            100, // 100 tickets
            4 // max 4 tickets per purchase
        );
        
        vm.stopPrank();
        
        // Step 2: Buy ticket as buyer
        vm.startPrank(buyer);
        
        // Approve IDRX spending
        idrx.approve(eventAddress, 1000 * 10**2);
        
        // Buy ticket
        event_.purchaseTicket(0, 2); // Buy 2 tickets of tier 0
        
        vm.stopPrank();
        
        // Verify tickets were sold
        (,, uint256 available, uint256 sold,,) = Event(eventAddress).ticketTiers(0);
        assertEq(sold, 2);
        assertEq(available, 100);
        
        // Verify NFTs were minted to buyer
        address ticketNFTAddress = event_.getTicketNFT();
        ITicketNFT ticketNFT = ITicketNFT(ticketNFTAddress);
        assertEq(ticketNFT.balanceOf(buyer), 2);
    }
}