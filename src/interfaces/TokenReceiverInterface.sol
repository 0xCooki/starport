pragma solidity =0.8.17;

interface TokenReceiverInterface {
  function onERC721Received(
    address operator,
    address from,
    uint256 tokenId,
    bytes calldata data
  ) external virtual returns (bytes4);

  function onERC1155Received(
    address,
    address,
    uint256,
    uint256,
    bytes calldata
  ) external virtual returns (bytes4);

  function onERC1155BatchReceived(
    address,
    address,
    uint256[] calldata,
    uint256[] calldata,
    bytes calldata
  ) external virtual returns (bytes4);
}
