pragma solidity =0.8.17;

import {ERC721} from "solady/src/tokens/ERC721.sol";
import {ERC20} from "solady/src/tokens/ERC20.sol";
import {ERC1155} from "solady/src/tokens/ERC1155.sol";

import {
  ItemType,
  Schema,
  SpentItem,
  ReceivedItem
} from "seaport-types/src/lib/ConsiderationStructs.sol";

import {
  ContractOffererInterface
} from "seaport-types/src/interfaces/ContractOffererInterface.sol";
import {
  TokenReceiverInterface
} from "src/interfaces/TokenReceiverInterface.sol";
import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";
import {Originator} from "src/originators/Originator.sol";
import {SettlementHook} from "src/hooks/SettlementHook.sol";
import {SettlementHandler} from "src/handlers/SettlementHandler.sol";
import {Pricing} from "src/pricing/Pricing.sol";
import {LoanManager} from "src/LoanManager.sol";
import "forge-std/console.sol";

contract Custodian is ContractOffererInterface, TokenReceiverInterface {
  LoanManager public immutable LM;
  address public immutable seaport;

  constructor(LoanManager LM_, address seaport_) {
    seaport = seaport_;
    LM = LM_;
  }

  function supportsInterface(
    bytes4 interfaceId
  ) public view virtual override(ContractOffererInterface) returns (bool) {
    return interfaceId == type(ContractOffererInterface).interfaceId;
  }

  modifier onlySeaport() {
    if (msg.sender != address(seaport)) {
      revert InvalidSender();
    }
    _;
  }

  error InvalidSender();
  error InvalidHandler();

  /**
   * @dev Generates the order for this contract offerer.
   *
   * @param offer            The address of the contract fulfiller.
   * @param consideration    The maximum amount of items to be spent by the order.
   * @param context          The context of the order.
   * @param orderHashes      The context of the order.
   * @param contractNonce    The context of the order.
   * @return ratifyOrderMagicValue The magic value returned by the ratify.
   */
  function ratifyOrder(
    SpentItem[] calldata offer,
    ReceivedItem[] calldata consideration,
    bytes calldata context, // encoded based on the schemaID
    bytes32[] calldata orderHashes,
    uint256 contractNonce
  ) external onlySeaport returns (bytes4 ratifyOrderMagicValue) {
    LoanManager.Loan memory loan = abi.decode(context, (LoanManager.Loan));
    //ensure loan is valid against what we have to deliver to seaport
    ratifyOrderMagicValue = ContractOffererInterface.ratifyOrder.selector;
    // we burn the loan on repayment in generateOrder, but in ratify order where we would trigger any post settlement actions
    // we burn it here so that in the case it was minted and an owner is set for settlement their pointer can still be utilized
    if (!LM.active(loan)) {
      // on repayment handler for originator here?
      // they can do post state follow up, but have no rentrancy capabilities here as we havent left seaport
    } else {
      if (
        SettlementHandler(loan.terms.handler).execute(loan) !=
        SettlementHandler.execute.selector
      ) {
        revert InvalidHandler();
      }
      LM.settle(loan);
    }
  }

  function custody(
    ReceivedItem[] calldata consideration,
    bytes32[] calldata orderHashes,
    uint256 contractNonce,
    bytes calldata context
  ) external virtual returns (bytes4 selector) {
    selector = Custodian.custody.selector;
  }

  /**
   * @dev Generates the order for this contract offerer.
   *
   * @param fulfiller        The address of the contract fulfiller.
   * @param maximumSpent     The maximum amount of items to be spent by the order.
   * @param context          The context of the order.
   * @return offer           The items spent by the order.
   * @return consideration   The items received by the order.
   */
  function generateOrder(
    address fulfiller,
    SpentItem[] calldata minimumReceived,
    SpentItem[] calldata maximumSpent,
    bytes calldata context // encoded based on the schemaID
  )
    external
    onlySeaport
    returns (SpentItem[] memory offer, ReceivedItem[] memory consideration)
  {
    LoanManager.Loan memory loan = abi.decode(context, (LoanManager.Loan));
    offer = loan.collateral;
    ReceivedItem[] memory feeConsideration = Originator(loan.originator)
      .getFeeConsideration(loan);
    bool originatorFeeOn = feeConsideration.length > 0;

    if (SettlementHook(loan.terms.hook).isActive(loan)) {
      if (fulfiller != loan.borrower) {
        revert InvalidSender();
      }
      ReceivedItem[] memory paymentConsideration = Pricing(loan.terms.pricing)
        .getPaymentConsideration(loan);

      consideration = new ReceivedItem[](
        originatorFeeOn
          ? paymentConsideration.length + feeConsideration.length
          : paymentConsideration.length
      );
      uint256 offset;
      uint256 i = 0;

      if (originatorFeeOn) {
        for (; i < feeConsideration.length; ) {
          consideration[i] = feeConsideration[i];
          unchecked {
            ++i;
          }
        }
        offset = feeConsideration.length;
        i = 0;
      }

      for (; i < paymentConsideration.length; ) {
        consideration[i + offset] = paymentConsideration[i];
        unchecked {
          ++i;
        }
      }

      LM.settle(loan);
    } else {
      address restricted;
      //add in originator fee
      (consideration, restricted) = SettlementHandler(loan.terms.handler)
        .getSettlement(loan);

      if (restricted != address(0) && fulfiller != restricted) {
        revert InvalidSender();
      }
    }

    if (offer.length > 0) {
      _beforeApprovalsSetHook(fulfiller, maximumSpent, context);
      _setOfferApprovals(offer, seaport);
    }
  }

  function _beforeApprovalsSetHook(
    address fulfiller,
    SpentItem[] calldata maximumSpent,
    bytes calldata context
  ) internal virtual {}

  function _setOfferApprovals(
    SpentItem[] memory offer,
    address target
  ) internal {
    for (uint256 i = 0; i < offer.length; i++) {
      //approve consideration based on item type
      if (offer[i].itemType == ItemType.ERC1155) {
        ERC1155(offer[i].token).setApprovalForAll(target, true);
      } else if (offer[i].itemType == ItemType.ERC721) {
        ERC721(offer[i].token).setApprovalForAll(target, true);
      } else if (offer[i].itemType == ItemType.ERC20) {
        uint256 allowance = ERC20(offer[i].token).allowance(
          address(this),
          target
        );
        if (allowance != 0) {
          ERC20(offer[i].token).approve(target, 0);
        }
        ERC20(offer[i].token).approve(target, offer[i].amount);
      }
    }
  }

  /**
   * @dev previews the order for this contract offerer.
   *
   * @param caller        The address of the contract fulfiller.
   * @param fulfiller        The address of the contract fulfiller.
   * @param minimumReceived  The minimum the fulfiller must receive.
   * @param maximumSpent     The most a fulfiller will spend
   * @param context          The context of the order.
   * @return offer     The items spent by the order.
   * @return consideration  The items received by the order.
   */
  function previewOrder(
    address caller,
    address fulfiller,
    SpentItem[] calldata minimumReceived,
    SpentItem[] calldata maximumSpent,
    bytes calldata context // encoded based on the schemaID
  )
    public
    view
    returns (SpentItem[] memory offer, ReceivedItem[] memory consideration)
  {
    //TODO: move this into generate order and then do a view only version that doesnt call settle
  }

  function getSeaportMetadata()
    external
    pure
    returns (string memory, Schema[] memory schemas)
  {
    schemas = new Schema[](1);
    schemas[0] = Schema(8, "");
    return ("Loans", schemas);
  }

  // PUBLIC FUNCTIONS
  function onERC721Received(
    address operator,
    address from,
    uint256 tokenId,
    bytes calldata data
  ) public pure virtual returns (bytes4) {
    return TokenReceiverInterface.onERC721Received.selector;
  }

  function onERC1155Received(
    address,
    address,
    uint256,
    uint256,
    bytes calldata
  ) external pure virtual returns (bytes4) {
    return TokenReceiverInterface.onERC1155Received.selector;
  }

  function onERC1155BatchReceived(
    address,
    address,
    uint256[] calldata,
    uint256[] calldata,
    bytes calldata
  ) external pure virtual returns (bytes4) {
    return TokenReceiverInterface.onERC1155BatchReceived.selector;
  }
}
