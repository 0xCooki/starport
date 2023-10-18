import "starport-test/StarPortTest.sol";
import {StarPortLib} from "starport-core/lib/StarPortLib.sol";

contract MockOriginator is StrategistOriginator, TokenReceiverInterface {
    constructor(LoanManager LM_, address strategist_, uint256 fee_)
        StrategistOriginator(LM_, strategist_, fee_, msg.sender)
    {}

    // PUBLIC FUNCTIONS
    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data)
        public
        pure
        virtual
        returns (bytes4)
    {
        return TokenReceiverInterface.onERC721Received.selector;
    }

    function onERC1155Received(address, address, uint256, uint256, bytes calldata)
        external
        pure
        virtual
        returns (bytes4)
    {
        return TokenReceiverInterface.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata)
        external
        pure
        virtual
        returns (bytes4)
    {
        return TokenReceiverInterface.onERC1155BatchReceived.selector;
    }

    function terms(bytes calldata) public view returns (LoanManager.Terms memory) {
        return LoanManager.Terms({
            hook: address(0),
            handler: address(0),
            pricing: address(0),
            pricingData: new bytes(0),
            handlerData: new bytes(0),
            hookData: new bytes(0)
        });
    }

    function execute(Request calldata request) external override returns (Response memory response) {
        return Response({terms: terms(request.details), issuer: address(this)});
    }
}

contract TestLoanManager is StarPortTest {
    using Cast for *;

    LoanManager.Loan public activeLoan;

    using {StarPortLib.getId} for LoanManager.Loan;

    function setUp() public virtual override {
        super.setUp();
    }

    function testName() public {
        assertEq(LM.name(), "Starport Loan Manager");
    }

    function testSymbol() public {
        assertEq(LM.symbol(), "SLM");
    }

    function testSupportsInterface() public {
        assertTrue(LM.supportsInterface(type(ContractOffererInterface).interfaceId));
        assertTrue(LM.supportsInterface(type(ERC721).interfaceId));
        assertTrue(LM.supportsInterface(bytes4(0x5b5e139f)));
        assertTrue(LM.supportsInterface(bytes4(0x01ffc9a7)));
    }

    function testGenerateOrderNotSeaport() public {
        vm.expectRevert(abi.encodeWithSelector(LoanManager.NotSeaport.selector));
        LM.generateOrder(address(this), new SpentItem[](0), new SpentItem[](0), new bytes(0));
    }

    function testGenerateOrder() public {
        StrategistOriginator originator = new MockOriginator(LM, address(0), 0);
        address seaport = address(LM.seaport());
        debt.push(SpentItem({itemType: ItemType.ERC20, token: address(erc20s[0]), amount: 100, identifier: 0}));

        SpentItem[] memory maxSpent = new SpentItem[](1);
        maxSpent[0] = SpentItem({token: address(erc721s[0]), amount: 1, identifier: 1, itemType: ItemType.ERC721});

        //
        LoanManager.Obligation memory O = LoanManager.Obligation({
            custodian: address(custodian),
            borrower: borrower.addr,
            debt: debt,
            salt: bytes32(0),
            details: "",
            approval: "",
            caveats: new LoanManager.Caveat[](0),
            originator: address(originator)
        });

        //        OrderParameters memory op = _buildContractOrder(address(LM), new OfferItem[](0), selectedCollateral);
        vm.startPrank(seaport);
        (SpentItem[] memory offer, ReceivedItem[] memory consideration) =
            LM.generateOrder(address(this), new SpentItem[](0), maxSpent, abi.encode(O));
        //TODO:: validate return data matches request
        //        assertEq(keccak256(abi.encode(consideration)), keccak256(abi.encode(maxSpent)));
    }
}