"""Hidden cocotb testbench for sources/rdwrarbt.sv — matches golden/rdwrarbt.sv."""

from __future__ import annotations

import os
import random
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, NextTimeStep, ReadOnly, RisingEdge, Timer
from cocotb_tools.runner import get_runner

CLK_PERIOD_NS = 10

PRIORITY_ORDERS: dict[int, list[int]] = {
    0: [0, 1, 2, 3],
    1: [1, 2, 3, 0],
    2: [2, 3, 0, 1],
    3: [3, 0, 1, 2],
}


def next_fib_reg(fib: int, seed0: int) -> int:
    new_bit = ((fib >> 3) & 1) ^ ((fib >> 2) & 1) ^ (seed0 & 1)
    return ((fib << 1) | new_bit) & 0xF


def expected_grant(req: int, priority_mode: int) -> int:
    for master in PRIORITY_ORDERS[priority_mode & 0x3]:
        if (req >> master) & 1:
            return 1 << master
    return 0


def expected_bank_outputs(
    gnt: int,
    cmd: int,
    addr0: int,
    addr1: int,
    addr2: int,
    addr3: int,
) -> dict[str, int]:
    """
    Golden routing: granted master routes by address LSB parity.
      even address (LSB=0) -> bank0
      odd address  (LSB=1) -> bank1
    """
    out = {
        "bank0_req": 0,
        "bank0_cmd": 0,
        "bank0_addr": 0,
        "bank1_req": 0,
        "bank1_cmd": 0,
        "bank1_addr": 0,
    }

    addrs = [addr0, addr1, addr2, addr3]
    for master in range(4):
        if not (gnt & (1 << master)):
            continue
        addr = addrs[master]
        master_cmd = (cmd >> master) & 1
        if (addr & 1) == 0:
            out["bank0_req"] = 1
            out["bank0_cmd"] = master_cmd
            out["bank0_addr"] = addr
        else:
            out["bank1_req"] = 1
            out["bank1_cmd"] = master_cmd
            out["bank1_addr"] = addr
        break

    return out


def logic_to_int(value, name: str) -> int:
    if not value.is_resolvable:
        raise AssertionError(f"{name} is X/Z — is sources/rdwrarbt.sv implemented?")
    return int(value)


async def start_clock(dut) -> None:
    Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start()


async def drive_idle(dut) -> None:
    dut.seed_in.value = 0
    dut.master_req.value = 0
    dut.master_cmd.value = 0
    dut.master_addr_0.value = 0
    dut.master_addr_1.value = 0
    dut.master_addr_2.value = 0
    dut.master_addr_3.value = 0


async def apply_reset(dut, cycles: int = 3) -> None:
    dut.rst_n.value = 0
    await drive_idle(dut)
    for _ in range(cycles):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await NextTimeStep()


def read_outputs(dut) -> dict[str, int]:
    return {
        "master_gnt": logic_to_int(dut.master_gnt.value, "master_gnt"),
        "bank0_req": logic_to_int(dut.bank0_req.value, "bank0_req"),
        "bank0_cmd": logic_to_int(dut.bank0_cmd.value, "bank0_cmd"),
        "bank0_addr": logic_to_int(dut.bank0_addr.value, "bank0_addr"),
        "bank1_req": logic_to_int(dut.bank1_req.value, "bank1_req"),
        "bank1_cmd": logic_to_int(dut.bank1_cmd.value, "bank1_cmd"),
        "bank1_addr": logic_to_int(dut.bank1_addr.value, "bank1_addr"),
    }


async def sample_outputs_after_inputs(dut) -> dict[str, int]:
    await Timer(1, unit="ns")
    await ReadOnly()
    return read_outputs(dut)


async def set_master_inputs(
    dut,
    req: int,
    cmd: int,
    addr0: int = 0,
    addr1: int = 0,
    addr2: int = 0,
    addr3: int = 0,
) -> None:
    await NextTimeStep()
    dut.master_req.value = req & 0xF
    dut.master_cmd.value = cmd & 0xF
    dut.master_addr_0.value = addr0 & 0xFFFFFFFF
    dut.master_addr_1.value = addr1 & 0xFFFFFFFF
    dut.master_addr_2.value = addr2 & 0xFFFFFFFF
    dut.master_addr_3.value = addr3 & 0xFFFFFFFF


def assert_one_hot_grant(gnt: int) -> None:
    assert gnt == 0 or (gnt & (gnt - 1)) == 0, (
        f"master_gnt must be zero or one-hot, got {gnt:#05b}"
    )


def read_fib_pri_reg(dut) -> int:
    return logic_to_int(dut.fib_pri_reg.value, "fib_pri_reg")


async def advance_fib_to_mode(dut, target_mode: int, seed0: int = 0, max_cycles: int = 32) -> None:
    await NextTimeStep()
    dut.seed_in.value = seed0
    for _ in range(max_cycles):
        if read_fib_pri_reg(dut) & 0x3 == (target_mode & 0x3):
            return
        await RisingEdge(dut.clk)
    raise RuntimeError(
        f"fib_pri_reg[1:0] did not reach mode {target_mode} in {max_cycles} cycles"
    )


async def check_scenario(
    dut,
    req: int,
    cmd: int,
    addr0: int = 0,
    addr1: int = 0,
    addr2: int = 0,
    addr3: int = 0,
) -> None:
    await set_master_inputs(dut, req, cmd, addr0, addr1, addr2, addr3)
    observed = await sample_outputs_after_inputs(dut)
    priority_mode = read_fib_pri_reg(dut) & 0x3
    expected_gnt = expected_grant(req, priority_mode)
    expected_banks = expected_bank_outputs(
        expected_gnt, cmd, addr0, addr1, addr2, addr3
    )

    assert_one_hot_grant(observed["master_gnt"])
    assert observed["master_gnt"] == expected_gnt, (
        f"priority mode {priority_mode}: req={req:#05b}, "
        f"expected gnt={expected_gnt:#05b}, got {observed['master_gnt']:#05b}"
    )
    for key, expected in expected_banks.items():
        assert observed[key] == expected, (
            f"priority mode {priority_mode}: {key} expected {expected}, got {observed[key]}"
        )


@cocotb.test()
async def reset_idle_outputs_test(dut):
    await start_clock(dut)
    await apply_reset(dut)
    await drive_idle(dut)
    observed = await sample_outputs_after_inputs(dut)
    assert observed["master_gnt"] == 0
    assert observed["bank0_req"] == 0
    assert observed["bank1_req"] == 0
    assert read_fib_pri_reg(dut) == 0x1


@cocotb.test()
async def fib_priority_register_test(dut):
    await start_clock(dut)
    await apply_reset(dut)

    fib = read_fib_pri_reg(dut)
    await FallingEdge(dut.clk)
    dut.seed_in.value = 1
    await Timer(1, unit="ns")
    for _ in range(8):
        await RisingEdge(dut.clk)
        await Timer(1, unit="ns")
        expected = next_fib_reg(fib, seed0=1)
        fib = read_fib_pri_reg(dut)
        assert fib == expected, f"expected fib_pri_reg={expected:#05b}, got {fib:#05b}"


@cocotb.test()
async def fib_priority_register_seed_zero_test(dut):
    await start_clock(dut)
    await apply_reset(dut)

    fib = read_fib_pri_reg(dut)
    await FallingEdge(dut.clk)
    dut.seed_in.value = 0
    await Timer(1, unit="ns")
    for _ in range(8):
        await RisingEdge(dut.clk)
        await Timer(1, unit="ns")
        expected = next_fib_reg(fib, seed0=0)
        fib = read_fib_pri_reg(dut)
        assert fib == expected, f"expected fib_pri_reg={expected:#05b}, got {fib:#05b}"


@cocotb.test()
async def mode0_m0_highest_priority_grant_test(dut):
    await start_clock(dut)
    await apply_reset(dut)
    await advance_fib_to_mode(dut, 0)
    await check_scenario(dut, req=0b0001, cmd=0b0001, addr0=0x0000_0100)


@cocotb.test()
async def mode0_m0_wins_over_lower_masters_test(dut):
    await start_clock(dut)
    await apply_reset(dut)
    await advance_fib_to_mode(dut, 0)
    await check_scenario(
        dut,
        req=0b1111,
        cmd=0b1010,
        addr0=0x0000_0200,
        addr1=0x0000_0005,
        addr2=0x0000_0006,
        addr3=0x0000_0009,
    )


@cocotb.test()
async def no_request_no_grant_test(dut):
    await start_clock(dut)
    await apply_reset(dut)

    for mode in range(4):
        await advance_fib_to_mode(dut, mode)
        await set_master_inputs(dut, req=0, cmd=0)
        observed = await sample_outputs_after_inputs(dut)
        assert observed["master_gnt"] == 0
        assert observed["bank0_req"] == 0
        assert observed["bank1_req"] == 0


@cocotb.test()
async def single_master_grant_test(dut):
    await start_clock(dut)
    await apply_reset(dut)

    addrs = [0x0000_0000, 0x0000_0003, 0x0000_0002, 0x0000_0007]
    for mode in range(4):
        await advance_fib_to_mode(dut, mode)
        for master in range(4):
            req = 1 << master
            await check_scenario(
                dut,
                req=req,
                cmd=req,
                addr0=addrs[0],
                addr1=addrs[1],
                addr2=addrs[2],
                addr3=addrs[3],
            )


@cocotb.test()
async def multi_master_arbitration_test(dut):
    await start_clock(dut)
    await apply_reset(dut)

    scenarios = [
        (0x0F, 0x0000_0000, 0x0000_0003, 0x0000_0002, 0x0000_0007),
        (0x0A, 0x0000_0010, 0x0000_0013, 0x0000_0014, 0x0000_0017),
        (0x05, 0x0000_0020, 0x0000_0021, 0x0000_0022, 0x0000_0025),
        (0x0C, 0x0000_0030, 0x0000_0031, 0x0000_0032, 0x0000_0037),
    ]

    for mode in range(4):
        await advance_fib_to_mode(dut, mode)
        for req, a0, a1, a2, a3 in scenarios:
            await check_scenario(dut, req=req, cmd=req, addr0=a0, addr1=a1, addr2=a2, addr3=a3)


@cocotb.test()
async def even_address_routes_to_bank0_test(dut):
    await start_clock(dut)
    await apply_reset(dut)

    await advance_fib_to_mode(dut, 0)
    await check_scenario(dut, req=0b0001, cmd=0b0001, addr0=0x0000_0100)

    await advance_fib_to_mode(dut, 1)
    await check_scenario(dut, req=0b0010, cmd=0b0010, addr1=0x0000_0200)

    await advance_fib_to_mode(dut, 2)
    await check_scenario(dut, req=0b0100, cmd=0b0100, addr2=0x0000_0300)


@cocotb.test()
async def odd_address_routes_to_bank1_test(dut):
    await start_clock(dut)
    await apply_reset(dut)

    await advance_fib_to_mode(dut, 0)
    await check_scenario(dut, req=0b0001, cmd=0b0001, addr0=0x0000_0101)

    await advance_fib_to_mode(dut, 2)
    await check_scenario(dut, req=0b0100, cmd=0b0100, addr2=0x0000_0303)

    await advance_fib_to_mode(dut, 3)
    await check_scenario(dut, req=0b1000, cmd=0b1000, addr3=0x0000_0407)


@cocotb.test()
async def parity_routing_all_masters_test(dut):
    """Any granted master: even addr -> bank0, odd addr -> bank1."""
    await start_clock(dut)
    await apply_reset(dut)

    await advance_fib_to_mode(dut, 0)
    await set_master_inputs(dut, req=0b0001, cmd=0b0001, addr0=0x0000_0001)
    observed = await sample_outputs_after_inputs(dut)
    assert observed["master_gnt"] == 0b0001
    assert observed["bank0_req"] == 0
    assert observed["bank1_req"] == 1
    assert observed["bank1_addr"] == 0x0000_0001

    await advance_fib_to_mode(dut, 2)
    await set_master_inputs(dut, req=0b0100, cmd=0b0100, addr2=0x0000_0002)
    observed = await sample_outputs_after_inputs(dut)
    assert observed["master_gnt"] == 0b0100
    assert observed["bank0_req"] == 1
    assert observed["bank0_addr"] == 0x0000_0002
    assert observed["bank1_req"] == 0


@cocotb.test()
async def read_command_propagation_test(dut):
    await start_clock(dut)
    await apply_reset(dut)
    await advance_fib_to_mode(dut, 2)

    await check_scenario(dut, req=0b0100, cmd=0b0000, addr2=0x0000_000B)
    await check_scenario(dut, req=0b1000, cmd=0b1000, addr3=0x0000_000F)


@cocotb.test()
async def priority_rotation_smoke_test(dut):
    await start_clock(dut)
    await apply_reset(dut)

    req = 0b1111
    cmd = 0b0101
    addrs = [0x0000_0100, 0x0000_0103, 0x0000_0102, 0x0000_0107]

    seen_modes: set[int] = set()
    for _ in range(16):
        seen_modes.add(read_fib_pri_reg(dut) & 0x3)
        await check_scenario(
            dut,
            req=req,
            cmd=cmd,
            addr0=addrs[0],
            addr1=addrs[1],
            addr2=addrs[2],
            addr3=addrs[3],
        )
        await RisingEdge(dut.clk)

    assert seen_modes == {0, 1, 2, 3}, f"expected all priority modes, saw {seen_modes}"


@cocotb.test()
async def random_stimulus_regression_test(dut):
    await start_clock(dut)
    await apply_reset(dut)

    rng = random.Random(0xC0C0_7B)
    for _ in range(64):
        await NextTimeStep()
        dut.seed_in.value = rng.randrange(0, 2)
        await RisingEdge(dut.clk)

        req = rng.randrange(0, 16)
        cmd = rng.randrange(0, 16)
        addrs = [rng.randrange(0, 0x1000) for _ in range(4)]
        await check_scenario(
            dut,
            req=req,
            cmd=cmd,
            addr0=addrs[0],
            addr1=addrs[1],
            addr2=addrs[2],
            addr3=addrs[3],
        )


def test_rdwrarbt_hidden_runner():
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent.parent
    sources = [proj_path / "sources" / "rdwrarbt.sv"]

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="rdwrarbt",
        always=True,
    )
    runner.test(
        hdl_toplevel="rdwrarbt",
        test_module=Path(__file__).stem,
    )
