import { execSync } from "node:child_process"
import { describe, it, expect } from "vitest"

const image = "pathline-powershell-test"
const cwd = process.cwd()

execSync(`docker build -t ${image} -f docker/powershell.Dockerfile .`, {
    cwd,
    stdio: "pipe",
    timeout: 120_000,
})

const output = execSync(
    `docker run --rm -v "${cwd}/src:/pathline/src:ro" -v "${cwd}/tests:/pathline/tests:ro" ${image} pwsh /pathline/tests/powershell-docker.ps1`,
    { encoding: "utf-8", timeout: 60_000 },
)

interface TestResult {
    name: string
    pass: boolean
    expected?: string
    actual?: string
}

const results: TestResult[] = output
    .trim()
    .split("\n")
    .filter((line) => line.startsWith("{"))
    .map((line) => JSON.parse(line))

describe("powershell tests (Docker)", () => {
    for (const result of results) {
        it(result.name, () => {
            if (!result.pass) {
                expect.fail(
                    `Expected: ${result.expected}\nActual: ${result.actual}`,
                )
            }
        })
    }
})
