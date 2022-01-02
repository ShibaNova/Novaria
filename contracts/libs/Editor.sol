// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "@openzeppelin/contracts/access/Ownable.sol";
contract Editor is Ownable {

    mapping (address => bool) public editor;
    
        // Addresses that can purchase ships
     modifier onlyEditor {
        require(isEditor(msg.sender));
        _;
    }
    // Is address a editor?
    function isEditor(address _editor) public view returns (bool){
        return editor[_editor] == true ? true : false;
    }
     // Add new editors
    function setEditor(address[] memory _editor) external onlyOwner {
        for (uint i = 0; i < _editor.length; i++) {
        require(editor[_editor[i]] == false, "DRYDOCK: Address is already a editor");
        editor[_editor[i]] = true;
        }
    }
    // Deactivate a editor
    function deactivateEditor ( address _editor) public onlyOwner {
        require(editor[_editor] == true, "DRYDOCK: Address is not a editor");
        editor[_editor] = false;
    }

}