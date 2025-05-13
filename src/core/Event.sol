// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "lib/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "src/libraries/Structs.sol";
import "src/libraries/Constants.sol";
import "src/libraries/TicketLib.sol";
import "src/interfaces/IEvent.sol";
import "src/interfaces/ITicketNFT.sol";
import "src/core/TicketNFT.sol";

contract Event is IEvent, ReentrancyGuard, Ownable {
    // Event details
    string public name;
    string public description;
    uint256 public date;
    string public venue;
    string public ipfsMetadata;
    address public organizer;
    bool public cancelled;
    
    // Contract references
    address public factory;
    ITicketNFT public ticketNFT;
    IERC20 public idrxToken;
    
    // Tiers and resale settings
    mapping(uint256 => Structs.TicketTier) public ticketTiers;
    uint256 public tierCount;
    Structs.ResaleRules public resaleRules;
    
    // Resale listings
    mapping(uint256 => Structs.ListingInfo) public listings;
    
    // Fee receivers
    address public platformFeeReceiver;
    
    // Modifier to restrict access to organizer
    modifier onlyOrganizer() {
        require(msg.sender == organizer, "Only organizer can call this");
        _;
    }
    
    // Modifier to ensure event is not cancelled
    modifier eventActive() {
        require(!cancelled, "Event has been cancelled");
        _;
    }
    
    constructor() {
    _transferOwnership(msg.sender);
        factory = msg.sender;
    }
    
    // Initialize contract - called by factory
    function initialize(
        address _organizer,
        string memory _name,
        string memory _description,
        uint256 _date,
        string memory _venue,
        string memory _ipfsMetadata
    ) external override onlyOwner {
        organizer = _organizer;
        name = _name;
        description = _description;
        date = _date;
        venue = _venue;
        ipfsMetadata = _ipfsMetadata;
        
        // Setup default resale rules
        resaleRules = Structs.ResaleRules({
            allowResell: true,
            maxMarkupPercentage: Constants.DEFAULT_MAX_MARKUP_PERCENTAGE,
            organizerFeePercentage: 250, // 2.5%
            restrictResellTiming: false,
            minDaysBeforeEvent: 1,
            requireVerification: false
        });
        
        // Transfer ownership to organizer
        _transferOwnership(_organizer);
    }
    
    // Initialize ticket NFT contract
    function setTicketNFT(address _ticketNFT, address _idrxToken, address _platformFeeReceiver) external onlyOwner {
        require(address(ticketNFT) == address(0), "TicketNFT already set");
        ticketNFT = ITicketNFT(_ticketNFT);
        idrxToken = IERC20(_idrxToken);
        platformFeeReceiver = _platformFeeReceiver;
    }
    
    // Create new ticket tier
    function addTicketTier(
        string memory _name,
        uint256 _price,
        uint256 _available,
        uint256 _maxPerPurchase
    ) external override onlyOrganizer eventActive {
        require(_price > 0, "Price must be greater than zero");
        require(_available > 0, "Available tickets must be greater than zero");
        require(_maxPerPurchase > 0 && _maxPerPurchase <= _available, "Invalid max per purchase");
        
        uint256 tierId = tierCount;
        ticketTiers[tierId] = Structs.TicketTier({
            name: _name,
            price: _price,
            available: _available,
            sold: 0,
            maxPerPurchase: _maxPerPurchase,
            active: true
        });
        
        tierCount++;
        
        emit TicketTierAdded(tierId, _name, _price);
    }
    
    // Update existing ticket tier
    function updateTicketTier(
        uint256 _tierId,
        string memory _name,
        uint256 _price,
        uint256 _available,
        uint256 _maxPerPurchase
    ) external override onlyOrganizer eventActive {
        require(_tierId < tierCount, "Tier does not exist");
        Structs.TicketTier storage tier = ticketTiers[_tierId];
        
        require(_price > 0, "Price must be greater than zero");
        require(_available >= tier.sold, "Available cannot be less than sold");
        require(_maxPerPurchase > 0 && _maxPerPurchase <= _available, "Invalid max per purchase");
        
        tier.name = _name;
        tier.price = _price;
        tier.available = _available;
        tier.maxPerPurchase = _maxPerPurchase;
        
        emit TicketTierUpdated(_tierId, _name, _price, _available);
    }
    
    // Purchase ticket(s)
    function purchaseTicket(uint256 _tierId, uint256 _quantity) external override nonReentrant eventActive {
        require(_tierId < tierCount, "Tier does not exist");
        Structs.TicketTier storage tier = ticketTiers[_tierId];
        
        // Validasi pembelian
        require(TicketLib.validateTicketPurchase(tier, _quantity), "Invalid purchase request");
        
        // Calculate total price
        uint256 totalPrice = tier.price * _quantity;
        
        // Transfer IDRX token dari pembeli ke kontrak event
        require(idrxToken.transferFrom(msg.sender, address(this), totalPrice), "Token transfer failed");
        
        // Calculate platform fee
        uint256 platformFee = (totalPrice * Constants.PLATFORM_FEE_PERCENTAGE) / Constants.BASIS_POINTS;
        
        // Transfer platform fee
        require(idrxToken.transfer(platformFeeReceiver, platformFee), "Platform fee transfer failed");
        
        // Transfer organizer share
        uint256 organizerShare = totalPrice - platformFee;
        require(idrxToken.transfer(organizer, organizerShare), "Organizer payment failed");
        
        // Mint NFT tickets
        for (uint256 i = 0; i < _quantity; i++) {
            ticketNFT.mintTicket(msg.sender, _tierId, tier.price);
        }
        
        // Update sold count
        tier.sold += _quantity;
        
        emit TicketPurchased(msg.sender, _tierId, _quantity);
    }
    
    // Set resale rules
    function setResaleRules(
        uint256 _maxMarkupPercentage,
        uint256 _organizerFeePercentage,
        bool _restrictResellTiming,
        uint256 _minDaysBeforeEvent
    ) external override onlyOrganizer {
        require(_maxMarkupPercentage <= 5000, "Max markup cannot exceed 50%"); // 50% = 5000 basis points
        require(_organizerFeePercentage <= 1000, "Organizer fee cannot exceed 10%"); // 10% = 1000 basis points
        
        resaleRules.maxMarkupPercentage = _maxMarkupPercentage;
        resaleRules.organizerFeePercentage = _organizerFeePercentage;
        resaleRules.restrictResellTiming = _restrictResellTiming;
        resaleRules.minDaysBeforeEvent = _minDaysBeforeEvent;
        
        emit ResaleRulesUpdated(_maxMarkupPercentage, _organizerFeePercentage);
    }
    
    // List ticket for resale
    function listTicketForResale(uint256 _tokenId, uint256 _price) external override nonReentrant eventActive {
        require(resaleRules.allowResell, "Resale not allowed for this event");
        require(ticketNFT.ownerOf(_tokenId) == msg.sender, "You don't own this ticket");
        
        // Get original price from metadata
        Structs.TicketMetadata memory metadata = ticketNFT.getTicketMetadata(_tokenId);
        require(!metadata.used, "Ticket has been used");
        
        // Validate resale price
        require(
            TicketLib.validateResalePrice(metadata.originalPrice, _price, resaleRules.maxMarkupPercentage),
            "Price exceeds maximum allowed"
        );
        
        // Check timing restrictions if enabled
        if (resaleRules.restrictResellTiming) {
            require(
                block.timestamp <= date - (resaleRules.minDaysBeforeEvent * 1 days),
                "Too close to event date"
            );
        }
        
        // Transfer ticket to contract
        ticketNFT.transferFrom(msg.sender, address(this), _tokenId);
        
        // Create listing
        listings[_tokenId] = Structs.ListingInfo({
            seller: msg.sender,
            price: _price,
            active: true,
            listingDate: block.timestamp
        });
        
        emit TicketListedForResale(_tokenId, _price);
    }
    
    // Buy resale ticket
    function purchaseResaleTicket(uint256 _tokenId) external override nonReentrant eventActive {
        Structs.ListingInfo storage listing = listings[_tokenId];
        require(listing.active, "Ticket not listed for resale");
        
        // Calculate fees
        (uint256 organizerFee, uint256 platformFee) = TicketLib.calculateFees(
            listing.price,
            resaleRules.organizerFeePercentage,
            Constants.PLATFORM_FEE_PERCENTAGE
        );
        
        // Calculate seller amount
        uint256 sellerAmount = listing.price - organizerFee - platformFee;
        
        // Transfer tokens from buyer
        require(idrxToken.transferFrom(msg.sender, address(this), listing.price), "Payment failed");
        
        // Transfer fees
        require(idrxToken.transfer(organizer, organizerFee), "Organizer fee transfer failed");
        require(idrxToken.transfer(platformFeeReceiver, platformFee), "Platform fee transfer failed");
        
        // Transfer seller amount
        require(idrxToken.transfer(listing.seller, sellerAmount), "Seller payment failed");
        
        // Transfer ticket to buyer
        ticketNFT.safeTransferFrom(address(this), msg.sender, _tokenId);
        
        // Mark ticket as transferred
        ticketNFT.markTransferred(_tokenId);
        
        // Clear listing
        delete listings[_tokenId];
        
        emit TicketResold(_tokenId, listing.seller, msg.sender, listing.price);
    }
    
    // Cancel a resale listing
    function cancelResaleListing(uint256 _tokenId) external nonReentrant {
        Structs.ListingInfo storage listing = listings[_tokenId];
        require(listing.active, "Ticket not listed for resale");
        require(listing.seller == msg.sender, "Not the seller");
        
        // Transfer ticket back to seller
        ticketNFT.safeTransferFrom(address(this), msg.sender, _tokenId);
        
        // Clear listing
        delete listings[_tokenId];
        
        emit ResaleListingCancelled(_tokenId, msg.sender);
    }
    
    // Cancel event - refunds would be handled by organizer
    function cancelEvent() external override onlyOrganizer {
        require(!cancelled, "Event already cancelled");
        cancelled = true;
        
        emit EventCancelled();
    }
    
    // Get ticket NFT contract address
    function getTicketNFT() external view override returns (address) {
        return address(ticketNFT);
    }
    
    // Events
    event TicketTierAdded(uint256 indexed tierId, string name, uint256 price);
    event TicketTierUpdated(uint256 indexed tierId, string name, uint256 price, uint256 available);
    event TicketPurchased(address indexed buyer, uint256 indexed tierId, uint256 quantity);
    event ResaleRulesUpdated(uint256 maxMarkupPercentage, uint256 organizerFeePercentage);
    event TicketListedForResale(uint256 indexed tokenId, uint256 price);
    event TicketResold(uint256 indexed tokenId, address indexed seller, address indexed buyer, uint256 price);
    event ResaleListingCancelled(uint256 indexed tokenId, address indexed seller);
    event EventCancelled();
}