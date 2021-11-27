// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @author Philippe Dumonet
contract HackaTUM_NFT is ERC721, Ownable {
    uint256 internal constant TEAM_COUNT = 25;
    uint256 internal constant MAX_TEAM_MEMBERS = 4;

    mapping(uint256 => uint256) public teamTokensMinted;
    mapping(uint256 => bool) public claimed;
    uint256 public claimDeadline;

    constructor(address[] memory _participants)
        payable
        ERC721("HackaTUM Quanstamp participation token", "TUMHAK")
        Ownable()
    {
        claimDeadline = block.timestamp + 31 days;
        for (uint256 i = 0; i < _participants.length; i++) {
            _initMint(_participants[i], i);
        }
    }

    function saveUnclaimed(uint256 _tokenId) external onlyOwner {
        require(!claimed[_tokenId], "HackaTUM_NFT: Already claimed");
        require(claimDeadline <= block.timestamp, "HackaTUM_NFT: Before deadline");
        _safeTransfer(ownerOf(_tokenId), msg.sender, _tokenId, "");
    }

    function mintForTeam(
        address _recipient,
        uint256 _teamId,
        uint256 _authTokenId
    ) external {
        require(ownerOf(_authTokenId) == msg.sender, "HackaTUM_NFT: Not owner");
        require(_authTokenId / MAX_TEAM_MEMBERS == _teamId, "HackaTUM_NFT: Wrong team");
        _mintTeamToken(_recipient, _teamId);
    }

    function claim(uint256 _tokenId) external {
        require(ownerOf(_tokenId) == msg.sender, "HackaTUM_NFT: Not owner");
        require(!claimed[_tokenId], "HackaTUM_NFT: Already claimed");
        claimed[_tokenId] = true;
    }

    function _baseURI() internal pure override returns (string memory) {
        return "ipfs://asdfsdfsdf/";
    }

    function _initMint(address _recipient, uint256 _teamId) internal {
        _mintTeamToken(_recipient, _teamId);
        payable(_recipient).transfer(0.1 ether);
    }

    function _beforeTokenTransfer(
        address _from,
        address _to,
        uint256 _tokenId
    ) internal override {
        super._beforeTokenTransfer(_from, _to, _tokenId);
        if (_from != address(0)) claimed[_tokenId] = true;
    }

    function _mintTeamToken(address _recipient, uint256 _teamId) internal {
        require(_teamId < TEAM_COUNT, "HackaTUM_NFT: Nonexistent team");
        uint256 tokensMinted = teamTokensMinted[_teamId];
        require(tokensMinted < MAX_TEAM_MEMBERS, "HackaTUM_NFT: Already minted all");
        _safeMint(_recipient, _teamId * MAX_TEAM_MEMBERS + tokensMinted);
        teamTokensMinted[_teamId] = tokensMinted + 1;
    }
}
