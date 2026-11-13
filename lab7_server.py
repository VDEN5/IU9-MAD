import asyncio
import json
import math
import random
import websockets

# ===== Константы =====
WALL_X = -8
WALL_H = 10
WALL_D = 8
HANDLE_LEN = 1.5
RACKET_R = 1.0
BALL_R = 0.15
BALL_SPEED = 4.0
Z_LIMIT = 4.0

PORT = 8060

RACKET_BASES = [
    {"x": 5.0, "y": -3.0, "dirSign": -1.0},
    {"x": 5.0, "y":  3.0, "dirSign": -1.0},
]

rackets = [
    {"id": 0, "angle": 0.0, "grab": 1.0, "offsetX": 0.0, "offsetY": 0.0, "offsetZ": 0.0},
    {"id": 1, "angle": 0.0, "grab": 1.0, "offsetX": 0.0, "offsetY": 0.0, "offsetZ": 0.0},
]

bx, by, bz = 0.0, 0.0, 0.0
bvx, bvy, bvz = 3.0, 1.2, 1.0

clients = set()
client_counter = 0


def closest_point_on_segment_3d(px, py, pz, x1, y1, z1, x2, y2, z2):
    dx, dy, dz = x2 - x1, y2 - y1, z2 - z1
    l2 = dx * dx + dy * dy + dz * dz
    t = 0.0 if l2 == 0 else ((px - x1) * dx + (py - y1) * dy + (pz - z1) * dz) / l2
    t = max(0.0, min(1.0, t))
    qx, qy, qz = x1 + t * dx, y1 + t * dy, z1 + t * dz
    ddx, ddy, ddz = px - qx, py - qy, pz - qz
    d = math.sqrt(ddx * ddx + ddy * ddy + ddz * ddz)
    return d, ddx, ddy, ddz


def reset_ball():
    global bx, by, bz, bvx, bvy, bvz
    bx, by, bz = 0.0, 0.0, 0.0
    bvx = -3.0
    bvy = (random.random() - 0.5) * 3
    bvz = (random.random() - 0.5) * 2


def tick():
    global bx, by, bz, bvx, bvy, bvz
    dt = 0.02
    nx = bx + bvx * dt
    ny = by + bvy * dt
    nz = bz + bvz * dt

    # Стенка слева
    if nx < WALL_X + 0.3 + BALL_R:
        nx = WALL_X + 0.3 + BALL_R
        bvx = abs(bvx)
    # Верх / низ
    if ny > WALL_H / 2 - BALL_R:
        ny = WALL_H / 2 - BALL_R
        bvy = -abs(bvy)
    if ny < -WALL_H / 2 + BALL_R:
        ny = -WALL_H / 2 + BALL_R
        bvy = abs(bvy)
    # Границы по Z
    if nz > Z_LIMIT - BALL_R:
        nz = Z_LIMIT - BALL_R
        bvz = -abs(bvz)
    if nz < -Z_LIMIT + BALL_R:
        nz = -Z_LIMIT + BALL_R
        bvz = abs(bvz)
    # Сброс
    if nx > 9:
        reset_ball()
        return

    # Столкновения с ракетками (3D)
    for r in rackets:
        base = RACKET_BASES[r["id"]]
        bxR = base["x"] + r["offsetX"]
        byR = base["y"] + r["offsetY"]
        bzR = r["offsetZ"]

        theta = r["angle"] * math.pi / 180
        ax = math.cos(theta) * base["dirSign"]
        ay = math.sin(theta)

        tipX = bxR + ax * (HANDLE_LEN + RACKET_R)
        tipY = byR + ay * (HANDLE_LEN + RACKET_R)
        tipZ = bzR

        d, ddx, ddy, ddz = closest_point_on_segment_3d(
            nx, ny, nz, bxR, byR, bzR, tipX, tipY, tipZ
        )
        hit_r = RACKET_R + BALL_R
        if 0.0001 < d < hit_r:
            ux, uy, uz = ddx / d, ddy / d, ddz / d
            dot = bvx * ux + bvy * uy + bvz * uz
            if dot < 0:
                bvx -= 2 * dot * ux
                bvy -= 2 * dot * uy
                bvz -= 2 * dot * uz
            push = hit_r - d + 0.05
            nx += ux * push
            ny += uy * push
            nz += uz * push

    # Постоянная скорость
    sp = math.sqrt(bvx * bvx + bvy * bvy + bvz * bvz)
    if sp > 0.001:
        bvx = bvx / sp * BALL_SPEED
        bvy = bvy / sp * BALL_SPEED
        bvz = bvz / sp * BALL_SPEED

    bx, by, bz = nx, ny, nz


async def broadcast():
    if not clients:
        return
    state = json.dumps({
        "type": "state",
        "bx": bx, "by": by, "bz": bz,
        "rackets": [
            {
                "id": r["id"],
                "angle": r["angle"],
                "grab": r["grab"],
                "offsetX": r["offsetX"],
                "offsetY": r["offsetY"],
                "offsetZ": r["offsetZ"],
            } for r in rackets
        ],
    })
    await asyncio.gather(
        *[c.send(state) for c in list(clients)],
        return_exceptions=True,
    )


async def handler(websocket):
    global client_counter
    cid = client_counter
    client_counter += 1
    clients.add(websocket)
    print(f"Client #{cid} connected. Total: {len(clients)}", flush=True)

    try:
        await websocket.send(json.dumps({"type": "welcome", "clientId": cid}))
        async for raw in websocket:
            try:
                data = json.loads(raw)
                if data.get("type") == "input":
                    rid = data.get("racketId")
                    if rid is not None and 0 <= rid < 2:
                        r = rackets[rid]
                        if "racketAngle" in data: r["angle"]   = float(data["racketAngle"])
                        if "grabAmount"  in data: r["grab"]    = float(data["grabAmount"])
                        if "offsetX"     in data: r["offsetX"] = float(data["offsetX"])
                        if "offsetY"     in data: r["offsetY"] = float(data["offsetY"])
                        if "offsetZ"     in data: r["offsetZ"] = float(data["offsetZ"])
            except Exception as e:
                print(f"Bad message from #{cid}: {e}", flush=True)
    except websockets.ConnectionClosed:
        pass
    finally:
        clients.discard(websocket)
        print(f"Client #{cid} disconnected. Total: {len(clients)}", flush=True)


async def tick_loop():
    while True:
        tick()
        await broadcast()
        await asyncio.sleep(0.016)


async def main():
    async with websockets.serve(handler, "0.0.0.0", PORT):
        print(f"Server started on ws://0.0.0.0:{PORT}", flush=True)
        await tick_loop()


if __name__ == "__main__":
    asyncio.run(main())