"""Hidden cocotb testbench for sources/rdwrarbt.sv — 8-master read/write arbiter."""

from __future__ import annotations

import os
import random
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, NextTimeStep, ReadOnly, RisingEdge, Timer
from cocotb_tools.runner import get_runner

CLK_PERIOD_NS = 10
NUM_MASTERS = 8

# Grant priority per rotation — matches the branches implemented in sources/rdwrarbt.sv
# (not the full 8-master spec for every rotation).
PRIORITY_ORDERS: dict[int, list[int]] = {
    0: [0, 1, 2, 3],
    1: [2, 3, 0],
    2: [4, 5, 6],
    3: [6, 7, 0],
}

ROTATION_BITS: dict[int, tuple[int, int]] = {
    0: (0, 0),
    1: (0, 1),
    2: (1, 0),
    3: (1, 1),
}


def next_fib_reg(fib: int, seed0: int) -> int:
    """Right-shift LFSR used in sources/rdwrarbt.sv."""
    b0 = (fib >> 0) & 1
    b1 = (fib >> 1) & 1
    b2 = (fib >> 2) & 1
    b3 = (fib >> 3) & 1
    new0 = b3 ^ b2 ^ (seed0 & 1)
    new1 = b0
    new2 = b1
    new3 = b2
    return new0 | (new1 << 1) | (new2 << 2) | (new3 << 3)


def expected_grant(reqs: list[int], priority_mode: int) -> int:
    for master in PRIORITY_ORDERS[priority_mode & 0x3]:
        if reqs[master]:
            return master
    return -1


def expected_bank_outputs(
    granted: int,
    cmds: list[int],
    addrs: list[int],
) -> dict[str, int]:
    out = {
        "bank0_req": 0,
        "bank0_cmd": 0,
        "bank0_addr": 0,
        "bank1_req": 0,
        "bank1_cmd": 0,
        "bank1_addr": 0,
    }
    if granted < 0:
        return out

    addr = addrs[granted]
    cmd = cmds[granted]
    if (addr & 1) == 0:
        out["bank0_req"] = 1
        out["bank0_cmd"] = cmd
        out["bank0_addr"] = addr
    else:
        out["bank1_req"] = 1
        out["bank1_cmd"] = cmd
        out["bank1_addr"] = addr
    return out


def logic_to_int(value, name: str) -> int:
    if not value.is_resolvable:
        raise AssertionError(f"{name} is X/Z — is sources/rdwrarbt.sv implemented?")
    return int(value)


async def start_clock(dut) -> None:
    Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start()


async def drive_idle(dut) -> None:
    dut.seed_in.value = 0
    for m in range(NUM_MASTERS):
        getattr(dut, f"master_req_{m}").value = 0
        getattr(dut, f"master_cmd_{m}").value = 0
        getattr(dut, f"master_addr_{m}").value = 0


async def apply_reset(dut, cycles: int = 3) -> None:
    dut.rst_n.value = 0
    await drive_idle(dut)
    for _ in range(cycles):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await NextTimeStep()


def read_fib_pri_reg(dut) -> int:
    return logic_to_int(dut.fib_pri_reg.value, "fib_pri_reg")


def read_priority_mode(dut) -> int:
    fib = read_fib_pri_reg(dut)
    return ((fib >> 1) & 1) << 1 | (fib & 1)


def read_grants(dut) -> int:
    mask = 0
    for m in range(NUM_MASTERS):
        if logic_to_int(getattr(dut, f"master_gnt_{m}").value, f"master_gnt_{m}"):
            mask |= 1 << m
    return mask


def read_stalls(dut) -> int:
    mask = 0
    for m in range(NUM_MASTERS):
        if logic_to_int(getattr(dut, f"stall_{m}").value, f"stall_{m}"):
            mask |= 1 << m
    return mask


def read_outputs(dut) -> dict[str, int]:
    return {
        "grants": read_grants(dut),
        "stalls": read_stalls(dut),
        "bank0_req": logic_to_int(dut.bank0_req.value, "bank0_req"),
        "bank0_cmd": logic_to_int(dut.bank0_cmd.value, "bank0_cmd"),
        "bank0_addr": logic_to_int(dut.bank0_addr.value, "bank0_addr"),
        "bank1_req": logic_to_int(dut.bank1_req.value, "bank1_req"),
        "bank1_cmd": logic_to_int(dut.bank1_cmd.value, "bank1_cmd"),
        "bank1_addr": logic_to_int(dut.bank1_addr.value, "bank1_addr"),
    }


async def sample_outputs(dut) -> dict[str, int]:
    await Timer(1, unit="ns")
    await ReadOnly()
    return read_outputs(dut)


def apply_master_inputs(
    dut,
    reqs: list[int],
    cmds: list[int],
    addrs: list[int],
) -> None:
    for m in range(NUM_MASTERS):
        getattr(dut, f"master_req_{m}").value = reqs[m] & 1
        getattr(dut, f"master_cmd_{m}").value = cmds[m] & 1
        getattr(dut, f"master_addr_{m}").value = addrs[m] & 0xFF


async def set_master_inputs(
    dut,
    reqs: list[int],
    cmds: list[int],
    addrs: list[int],
) -> None:
    await FallingEdge(dut.clk)
    apply_master_inputs(dut, reqs, cmds, addrs)


def assert_one_hot_grant(mask: int) -> None:
    assert mask == 0 or (mask & (mask - 1)) == 0, (
        f"grants must be zero or one-hot, got {mask:#05b}"
    )


async def advance_fib_to_mode(dut, target_mode: int, seed0: int = 0, max_cycles: int = 64) -> None:
    fib1, fib0 = ROTATION_BITS[target_mode & 0x3]
    await FallingEdge(dut.clk)
    dut.seed_in.value = seed0
    for _ in range(max_cycles):
        await RisingEdge(dut.clk)
        await ReadOnly()
        fib = read_fib_pri_reg(dut)
        if ((fib >> 1) & 1) == fib1 and (fib & 1) == fib0:
            await FallingEdge(dut.clk)
            return
    raise RuntimeError(
        f"fib_pri_reg[1:0] did not reach {fib1}{fib0} in {max_cycles} cycles"
    )


async def check_scenario(
    dut,
    reqs: list[int],
    cmds: list[int],
    addrs: list[int],
) -> None:
    apply_master_inputs(dut, reqs, cmds, addrs)
    await Timer(1, unit="ns")
    await ReadOnly()
    mode = read_priority_mode(dut)
    observed = read_outputs(dut)
    winner = expected_grant(reqs, mode)
    expected_mask = 0 if winner < 0 else (1 << winner)
    expected_banks = expected_bank_outputs(winner, cmds, addrs)

    assert_one_hot_grant(observed["grants"])
    assert observed["grants"] == expected_mask, (
        f"mode {mode}: reqs={[int(x) for x in reqs]}, "
        f"expected grant {expected_mask:#05b}, got {observed['grants']:#05b}"
    )
    for key, expected in expected_banks.items():
        assert observed[key] == expected, (
            f"mode {mode}: {key} expected {expected}, got {observed[key]}"
        )


@cocotb.test()
async def reset_idle_outputs_test(dut):
    await start_clock(dut)
    await apply_reset(dut)
    await drive_idle(dut)
    observed = await sample_outputs(dut)
    assert observed["grants"] == 0
    assert observed["stalls"] == 0
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
    for _ in range(12):
        await RisingEdge(dut.clk)
        await Timer(1, unit="ns")
        expected = next_fib_reg(fib, seed0=1)
        fib = read_fib_pri_reg(dut)
        assert fib == expected, f"expected fib_pri_reg={expected:#05b}, got {fib:#05b}"


@cocotb.test()
async def no_request_no_grant_test(dut):
    await start_clock(dut)
    await apply_reset(dut)

    idle = [0] * NUM_MASTERS
    for mode in range(4):
        await advance_fib_to_mode(dut, mode)
        await set_master_inputs(dut, idle, idle, idle)
        observed = await sample_outputs(dut)
        assert observed["grants"] == 0
        assert observed["bank0_req"] == 0
        assert observed["bank1_req"] == 0


@cocotb.test()
async def rotation00_m0_wins_test(dut):
    await start_clock(dut)
    await apply_reset(dut)
    await advance_fib_to_mode(dut, 0)

    reqs = [1] + [0] * 7
    cmds = [1] + [0] * 7
    addrs = [0x10] + [0] * 7
    await check_scenario(dut, reqs, cmds, addrs)


@cocotb.test()
async def rotation00_m0_beats_all_test(dut):
    await start_clock(dut)
    await apply_reset(dut)
    await advance_fib_to_mode(dut, 0)

    reqs = [1] * NUM_MASTERS
    cmds = [1] * NUM_MASTERS
    addrs = [0x20 + (m * 2) for m in range(NUM_MASTERS)]
    await check_scenario(dut, reqs, cmds, addrs)


@cocotb.test()
async def rotation01_m2_wins_test(dut):
    await start_clock(dut)
    await apply_reset(dut)
    await advance_fib_to_mode(dut, 1)

    reqs = [0, 0, 1] + [0] * 5
    cmds = [0, 0, 1] + [0] * 5
    addrs = [0, 0, 0x31] + [0] * 5
    await check_scenario(dut, reqs, cmds, addrs)


@cocotb.test()
async def rotation10_m4_wins_test(dut):
    await start_clock(dut)
    await apply_reset(dut)
    await advance_fib_to_mode(dut, 2)

    reqs = [0, 0, 0, 0, 1] + [0] * 3
    cmds = [0, 0, 0, 0, 1] + [0] * 3
    addrs = [0, 0, 0, 0, 0x40] + [0] * 3
    await check_scenario(dut, reqs, cmds, addrs)


@cocotb.test()
async def rotation11_m6_wins_test(dut):
    await start_clock(dut)
    await apply_reset(dut)
    await advance_fib_to_mode(dut, 3)

    reqs = [0] * 6 + [1, 0]
    cmds = [0] * 6 + [1, 0]
    addrs = [0] * 6 + [0x61, 0]
    await check_scenario(dut, reqs, cmds, addrs)


@cocotb.test()
async def even_address_routes_bank0_test(dut):
    await start_clock(dut)
    await apply_reset(dut)
    await advance_fib_to_mode(dut, 0)

    reqs = [1] + [0] * 7
    await check_scenario(dut, reqs, [1] + [0] * 7, [0x48] + [0] * 7)


@cocotb.test()
async def odd_address_routes_bank1_test(dut):
    await start_clock(dut)
    await apply_reset(dut)
    await advance_fib_to_mode(dut, 0)

    reqs = [1] + [0] * 7
    await check_scenario(dut, reqs, [1] + [0] * 7, [0x49] + [0] * 7)


@cocotb.test()
async def single_master_each_rotation_test(dut):
    await start_clock(dut)
    await apply_reset(dut)

    spot_checks = [
        (0, 0, 0x00),
        (1, 2, 0x22),
        (2, 4, 0x44),
        (3, 6, 0x66),
    ]
    for mode, master, addr in spot_checks:
        await advance_fib_to_mode(dut, mode)
        reqs = [0] * NUM_MASTERS
        cmds = [0] * NUM_MASTERS
        addrs = [0] * NUM_MASTERS
        reqs[master] = 1
        cmds[master] = 1
        addrs[master] = addr
        await check_scenario(dut, reqs, cmds, addrs)


@cocotb.test()
async def pipeline_stall_master0_test(dut):
    """Master 0 should stall when its address matches a valid pipeline stage."""
    await start_clock(dut)
    await apply_reset(dut)
    await advance_fib_to_mode(dut, 0)

    addr = 0x55
    reqs = [1] + [0] * 7
    cmds = [1] + [0] * 7
    addrs = [addr] + [0] * 7
    apply_master_inputs(dut, reqs, cmds, addrs)
    await RisingEdge(dut.clk)
    apply_master_inputs(dut, reqs, cmds, addrs)
    await Timer(1, unit="ns")
    await ReadOnly()
    assert read_stalls(dut) & 0x1, f"expected stall_0, stalls={read_stalls(dut):#05b}"


@cocotb.test()
async def pipeline_stall_master1_test(dut):
    await start_clock(dut)
    await apply_reset(dut)
    await advance_fib_to_mode(dut, 0)

    addr = 0x55
    reqs = [0, 1] + [0] * 6
    cmds = [0, 1] + [0] * 6
    addrs = [0, addr] + [0] * 6
    apply_master_inputs(dut, reqs, cmds, addrs)
    await RisingEdge(dut.clk)
    apply_master_inputs(dut, reqs, cmds, addrs)
    await Timer(1, unit="ns")
    await ReadOnly()
    assert read_stalls(dut) & 0x2, f"expected stall_1, stalls={read_stalls(dut):#05b}"


@cocotb.test()
async def priority_rotation_smoke_test(dut):
    await start_clock(dut)
    await apply_reset(dut)

    reqs = [1] * NUM_MASTERS
    cmds = [1] * NUM_MASTERS
    addrs = [0x10 + m for m in range(NUM_MASTERS)]

    seen_modes: set[int] = set()
    for _ in range(32):
        seen_modes.add(read_priority_mode(dut))
        await check_scenario(dut, reqs, cmds, addrs)
        await RisingEdge(dut.clk)

    assert seen_modes == {0, 1, 2, 3}, f"expected all modes, saw {seen_modes}"


@cocotb.test()
async def random_stimulus_regression_test(dut):
    await start_clock(dut)
    await apply_reset(dut)

    rng = random.Random(0xC0C07B)
    idle_req = [0] * NUM_MASTERS
    idle_cmd = [0] * NUM_MASTERS
    idle_addr = [0] * NUM_MASTERS

    for _ in range(48):
        dut.seed_in.value = rng.randrange(0, 2)
        await RisingEdge(dut.clk)

        reqs = [rng.randrange(0, 2) for _ in range(NUM_MASTERS)]
        cmds = [rng.randrange(0, 2) for _ in range(NUM_MASTERS)]
        addrs = [rng.randrange(0, 0x100) for _ in range(NUM_MASTERS)]
        await check_scenario(dut, reqs, cmds, addrs)

        await set_master_inputs(dut, idle_req, idle_cmd, idle_addr)
        await RisingEdge(dut.clk)


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
