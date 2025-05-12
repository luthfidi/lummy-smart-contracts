// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "forge-std/Test.sol";
import "src/core/EventFactory.sol";
import "src/core/Event.sol";
import "src/core/TicketNFT.sol";
import "src/libraries/Constants.sol";
import "src/libraries/Structs.sol";
import "forge-std/console.sol";

// Mock IDRX token untuk testing (sama seperti di EventFactory.t.sol)
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
        _decimals = 2; // IDRX memiliki 2 desimal
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
        
        // Jika allowance tidak terhingga (uint256 max value), jangan kurangi
        if (_allowances[sender][msg.sender] != type(uint256).max) {
            _approve(sender, msg.sender, _allowances[sender][msg.sender] - amount);
        }
        
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

contract EventTest is Test {
    // Kontrak untuk pengujian
    EventFactory public factory;
    Event public eventContract;
    ITicketNFT public ticketNFT;
    MockIDRX public idrx;
    
    // Alamat untuk pengujian
    address public deployer;
    address public organizer;
    address public buyer1;
    address public buyer2;
    address public reseller;
    
    // Data event
    uint256 public eventDate;
    address public eventAddress;
    string public eventName = "Concert Event";
    string public eventDescription = "A live music concert";
    string public eventVenue = "Jakarta Convention Center";
    string public eventIpfsMetadata = "ipfs://QmTestMetadata";
    
        // Setup untuk pengujian
    function setUp() public {
        console.log("Setting up Event test environment");
        
        // Buat alamat untuk testing
        deployer = makeAddr("deployer");
        organizer = makeAddr("organizer");
        buyer1 = makeAddr("buyer1");
        buyer2 = makeAddr("buyer2");
        reseller = makeAddr("reseller");
        
        // Set tanggal event (30 hari di masa depan)
        eventDate = block.timestamp + 30 days;
        
        // Deploy kontrak sebagai deployer
        vm.startPrank(deployer);
        
        // Deploy token IDRX
        idrx = new MockIDRX("IDRX Token", "IDRX");
        
        // Deploy EventFactory
        factory = new EventFactory(address(idrx));
        
        // Set platform fee receiver
        factory.setPlatformFeeReceiver(deployer);
        
        vm.stopPrank();
        
        // Mint IDRX ke akun pengujian (tidak perlu prank untuk kontrak test)
        idrx.mint(organizer, 10000 * 10**2); // 10,000 IDRX
        idrx.mint(buyer1, 5000 * 10**2);     // 5,000 IDRX
        idrx.mint(buyer2, 5000 * 10**2);     // 5,000 IDRX
        idrx.mint(reseller, 5000 * 10**2);   // 5,000 IDRX
        
        // Create Event directly to test the Event contract functionality
        // Deploy a new Event and TicketNFT manually to avoid any ownership issues
        vm.startPrank(organizer);
        
        // 1. Create Event contract
        eventContract = new Event();
        
        // 2. Initialize Event
        eventContract.initialize(
            organizer,
            eventName,
            eventDescription,
            eventDate,
            eventVenue,
            eventIpfsMetadata
        );
        
        // 3. Create TicketNFT
        TicketNFT ticketNFTContract = new TicketNFT();
        
        // 4. Initialize TicketNFT
        ticketNFTContract.initialize(eventName, "TIX", address(eventContract));
        
        // 5. Set TicketNFT in Event
        eventContract.setTicketNFT(address(ticketNFTContract), address(idrx), deployer);
        
        // Store address of Event
        eventAddress = address(eventContract);
        
        // Store the instance of TicketNFT
        ticketNFT = ITicketNFT(address(ticketNFTContract));
        
        vm.stopPrank();
        
        // Debug info
        console.log("Event owner:", eventContract.owner());
        console.log("Event created at:", eventAddress);
        console.log("TicketNFT created at:", address(ticketNFT));
    }
    
    // Test inisialisasi Event
    function testEventInitialization() public view {
        // Verifikasi data event
        assertEq(eventContract.name(), eventName);
        assertEq(eventContract.description(), eventDescription);
        assertEq(eventContract.date(), eventDate);
        assertEq(eventContract.venue(), eventVenue);
        assertEq(eventContract.ipfsMetadata(), eventIpfsMetadata);
        assertEq(eventContract.organizer(), organizer);
        assertEq(eventContract.cancelled(), false);
        
        // Verifikasi owner Event adalah organizer
        assertEq(Event(eventAddress).owner(), organizer);
    }
    
    // Test penambahan tier tiket
    function testAddTicketTier() public {
        // Setup tier tiket
        string memory tierName = "VIP";
        uint256 price = 200 * 10**2; // 200 IDRX
        uint256 available = 100;
        uint256 maxPerPurchase = 4;
        
        // Tambahkan tier tiket sebagai organizer
        vm.startPrank(organizer);
        eventContract.addTicketTier(
            tierName,
            price,
            available,
            maxPerPurchase
        );
        vm.stopPrank();
        
        // Verifikasi tier tiket berhasil ditambahkan
        (string memory name, uint256 tierPrice, uint256 tierAvailable, uint256 sold, uint256 tierMaxPerPurchase, bool active) = 
            eventContract.ticketTiers(0);
            
        assertEq(name, tierName);
        assertEq(tierPrice, price);
        assertEq(tierAvailable, available);
        assertEq(sold, 0);
        assertEq(tierMaxPerPurchase, maxPerPurchase);
        assertTrue(active);
        assertEq(eventContract.tierCount(), 1);
    }
    
    // Test update tier tiket
    function testUpdateTicketTier() public {
        // Tambahkan tier tiket terlebih dahulu
        vm.startPrank(organizer);
        eventContract.addTicketTier(
            "Regular",
            100 * 10**2,
            200,
            5
        );
        
        // Update tier tiket
        string memory updatedName = "Early Bird";
        uint256 updatedPrice = 80 * 10**2; // 80 IDRX (harga diskon)
        uint256 updatedAvailable = 150;
        uint256 updatedMaxPerPurchase = 3;
        
        eventContract.updateTicketTier(
            0, // tierId
            updatedName,
            updatedPrice,
            updatedAvailable,
            updatedMaxPerPurchase
        );
        vm.stopPrank();
        
        // Verifikasi tier tiket berhasil diupdate
        (string memory name, uint256 price, uint256 available, uint256 sold, uint256 maxPerPurchase, bool active) = 
            eventContract.ticketTiers(0);
            
        assertEq(name, updatedName);
        assertEq(price, updatedPrice);
        assertEq(available, updatedAvailable);
        assertEq(sold, 0);
        assertEq(maxPerPurchase, updatedMaxPerPurchase);
        assertTrue(active);
    }
    
    // Test pembelian tiket
    function testPurchaseTicket() public {
        // Tambahkan tier tiket
        vm.startPrank(organizer);
        eventContract.addTicketTier(
            "Regular",
            100 * 10**2, // 100 IDRX
            100, // 100 tiket
            4 // max 4 tiket per pembelian
        );
        vm.stopPrank();
        
        // Cek balance awal
        uint256 initialOrganizerBalance = idrx.balanceOf(organizer);
        uint256 initialPlatformBalance = idrx.balanceOf(deployer);
        
        // Pembeli approve penggunaan IDRX
        vm.startPrank(buyer1);
        idrx.approve(eventAddress, 500 * 10**2); // approve 500 IDRX
        
        // Beli 2 tiket
        uint256 quantity = 2;
        eventContract.purchaseTicket(0, quantity);
        vm.stopPrank();
        
        // Verifikasi jumlah tiket terjual
        (,, , uint256 sold,,) = eventContract.ticketTiers(0);
        assertEq(sold, quantity);
        
        // Verifikasi NFT berhasil dicetak
        assertEq(ticketNFT.balanceOf(buyer1), quantity);
        
        // Verifikasi fee platform dan pembayaran organizer
        uint256 ticketPrice = 100 * 10**2; // 100 IDRX
        uint256 totalPrice = ticketPrice * quantity;
        uint256 platformFee = (totalPrice * Constants.PLATFORM_FEE_PERCENTAGE) / Constants.BASIS_POINTS;
        uint256 organizerPayment = totalPrice - platformFee;
        
        assertEq(idrx.balanceOf(deployer) - initialPlatformBalance, platformFee);
        assertEq(idrx.balanceOf(organizer) - initialOrganizerBalance, organizerPayment);
    }
    
    // Test pengaturan aturan resale
    function testSetResaleRules() public {
        // Atur aturan resale sebagai organizer
        vm.startPrank(organizer);
        
        uint256 maxMarkupPercentage = 2000; // 20%
        uint256 organizerFeePercentage = 500; // 5%
        bool restrictResellTiming = true;
        uint256 minDaysBeforeEvent = 3;
        
        eventContract.setResaleRules(
            maxMarkupPercentage,
            organizerFeePercentage,
            restrictResellTiming,
            minDaysBeforeEvent
        );
        vm.stopPrank();
        
        // Verifikasi aturan resale
        (bool allowResell, uint256 rMaxMarkupPercentage, uint256 rOrganizerFeePercentage, 
         bool rRestrictResellTiming, uint256 rMinDaysBeforeEvent, bool requireVerification) = eventContract.resaleRules();
        
        assertTrue(allowResell); // default is true
        assertEq(rMaxMarkupPercentage, maxMarkupPercentage);
        assertEq(rOrganizerFeePercentage, organizerFeePercentage);
        assertEq(rRestrictResellTiming, restrictResellTiming);
        assertEq(rMinDaysBeforeEvent, minDaysBeforeEvent);
        assertEq(requireVerification, false); // default is false
    }
    
    // Helper function untuk setup tiket dan pembelian
    function _setupTicketsAndPurchase() internal {
        // Tambahkan tier tiket
        vm.startPrank(organizer);
        eventContract.addTicketTier(
            "Regular",
            100 * 10**2, // 100 IDRX
            100, // 100 tiket
            4 // max 4 tiket per pembelian
        );
        vm.stopPrank();
        
        // Beli tiket sebagai reseller
        vm.startPrank(reseller);
        idrx.approve(eventAddress, 200 * 10**2); // approve 200 IDRX
        eventContract.purchaseTicket(0, 2); // beli 2 tiket
        vm.stopPrank();
    }
    
    // Test listing tiket untuk resale
    function testListTicketForResale() public {
        // Setup tiket dan pembelian
        _setupTicketsAndPurchase();
        
        // Dapatkan token ID
        uint256 tokenId = 0; // Biasanya token ID pertama adalah 0
        
        // List tiket untuk resale
        vm.startPrank(reseller);
        
        // Approve kontrak event untuk mentransfer NFT
        ticketNFT.approve(eventAddress, tokenId);
        
        // Harga resale
        uint256 resalePrice = 120 * 10**2; // 120 IDRX (20% markup)
        
        // List untuk resale
        eventContract.listTicketForResale(tokenId, resalePrice);
        vm.stopPrank();
        
        // Verifikasi tiket berhasil di-list
        (address seller, uint256 price, bool active,) = eventContract.listings(tokenId);
        
        assertEq(seller, reseller);
        assertEq(price, resalePrice);
        assertTrue(active);
        
        // Verifikasi NFT ditransfer ke kontrak event
        assertEq(ticketNFT.ownerOf(tokenId), eventAddress);
    }
    
    // Test pembelian tiket resale
    function testPurchaseResaleTicket() public {
        // Setup tiket dan listing
        _setupTicketsAndPurchase();
        
        uint256 tokenId = 0;
        uint256 resalePrice = 120 * 10**2; // 120 IDRX (20% markup)
        
        // List tiket untuk resale
        vm.startPrank(reseller);
        ticketNFT.approve(eventAddress, tokenId);
        eventContract.listTicketForResale(tokenId, resalePrice);
        vm.stopPrank();
        
        // Cek saldo awal
        uint256 initialResellerBalance = idrx.balanceOf(reseller);
        uint256 initialOrganizerBalance = idrx.balanceOf(organizer);
        uint256 initialPlatformBalance = idrx.balanceOf(deployer);
        
        // Pembeli baru membeli tiket resale
        vm.startPrank(buyer2);
        idrx.approve(eventAddress, resalePrice);
        eventContract.purchaseResaleTicket(tokenId);
        vm.stopPrank();
        
        // Verifikasi kepemilikan NFT beralih ke pembeli baru
        assertEq(ticketNFT.ownerOf(tokenId), buyer2);
        
        // Verifikasi listing dihapus
        (, , bool active,) = eventContract.listings(tokenId);
        assertEq(active, false);
        
        // Verifikasi distribusi pembayaran
        // Platform Fee (1%)
        uint256 platformFee = (resalePrice * Constants.PLATFORM_FEE_PERCENTAGE) / Constants.BASIS_POINTS;
        
        // Organizer Fee (default 2.5%)
        (,, uint256 organizerFeePercentage,,,) = eventContract.resaleRules();
        uint256 organizerFee = (resalePrice * organizerFeePercentage) / Constants.BASIS_POINTS;
        
        // Jumlah yang diterima reseller
        uint256 sellerAmount = resalePrice - platformFee - organizerFee;
        
        assertEq(idrx.balanceOf(deployer) - initialPlatformBalance, platformFee);
        assertEq(idrx.balanceOf(organizer) - initialOrganizerBalance, organizerFee);
        assertEq(idrx.balanceOf(reseller) - initialResellerBalance, sellerAmount);
    }
    
    // Test pembatalan listing resale
    function testCancelResaleListing() public {
        // Setup tiket dan listing
        _setupTicketsAndPurchase();
        
        uint256 tokenId = 0;
        uint256 resalePrice = 120 * 10**2; // 120 IDRX
        
        // List tiket untuk resale
        vm.startPrank(reseller);
        ticketNFT.approve(eventAddress, tokenId);
        eventContract.listTicketForResale(tokenId, resalePrice);
        
        // Batalkan listing
        eventContract.cancelResaleListing(tokenId);
        vm.stopPrank();
        
        // Verifikasi listing dibatalkan
        (, , bool active,) = eventContract.listings(tokenId);
        assertEq(active, false);
        
        // Verifikasi NFT dikembalikan ke penjual
        assertEq(ticketNFT.ownerOf(tokenId), reseller);
    }
    
    // Test pembatalan event
    function testCancelEvent() public {
        // Batalkan event sebagai organizer
        vm.startPrank(organizer);
        eventContract.cancelEvent();
        vm.stopPrank();
        
        // Verifikasi event dibatalkan
        assertTrue(eventContract.cancelled());
    }
    
    // Test error: pembelian melebihi maxPerPurchase
    function testRevertIfBuyExceedingMaxPerPurchase() public {
        // Tambahkan tier tiket
        vm.startPrank(organizer);
        eventContract.addTicketTier(
            "Regular",
            100 * 10**2, // 100 IDRX
            100, // 100 tiket
            4 // max 4 tiket per pembelian
        );
        vm.stopPrank();
        
        // Mencoba membeli 5 tiket (melebihi maksimum 4)
        vm.startPrank(buyer1);
        idrx.approve(eventAddress, 500 * 10**2);
        
        // Ekspektasi akan revert
        vm.expectRevert("Quantity exceeds max per purchase");
        eventContract.purchaseTicket(0, 5); // Seharusnya gagal
        vm.stopPrank();
    }
    
    // Test error: akun selain organizer mencoba mengakses fungsi onlyOrganizer
    function testRevertIfNonOrganizerUpdateTicketTier() public {
        // Tambahkan tier tiket sebagai organizer
        vm.startPrank(organizer);
        eventContract.addTicketTier(
            "Regular",
            100 * 10**2,
            100,
            4
        );
        vm.stopPrank();
        
        // Buyer1 mencoba update tier (seharusnya gagal)
        vm.startPrank(buyer1);
        
        // Ekspektasi akan revert
        vm.expectRevert("Only organizer can call this");
        eventContract.updateTicketTier(
            0,
            "Updated Name",
            90 * 10**2,
            90,
            3
        );
        vm.stopPrank();
    }
    
    // Test error: List tiket dengan harga melebihi maksimum markup
    function testRevertIfListTicketExceedingMaxMarkup() public {
        // Setup tiket dan pembelian
        _setupTicketsAndPurchase();
        
        // Set markup maksimum 20%
        vm.startPrank(organizer);
        eventContract.setResaleRules(
            2000, // 20% maksimum markup
            250,  // 2.5% fee organizer
            false,
            1
        );
        vm.stopPrank();
        
        uint256 tokenId = 0;
        uint256 tooHighResalePrice = 150 * 10**2; // 150 IDRX (50% markup, melebihi batas)
        
        // Mencoba list dengan harga terlalu tinggi
        vm.startPrank(reseller);
        ticketNFT.approve(eventAddress, tokenId);
        
        // Ekspektasi akan revert dengan pesan error yang tepat
        vm.expectRevert("Resale price exceeds maximum allowed markup");
        eventContract.listTicketForResale(tokenId, tooHighResalePrice); // Seharusnya gagal
        vm.stopPrank();
    }
}