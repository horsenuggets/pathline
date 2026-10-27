import { execSync } from "node:child_process"
import { describe, it, expect } from "vitest"

const image = "pathline-shell-test"
const cwd = process.cwd()

execSync(`docker build -t ${image} -f docker/shell.Dockerfile .`, {
    cwd,
    stdio: "pipe",
    timeout: 120_000,
})

interface TestResult {
    name: string
    pass: boolean
    expected?: string
    actual?: string
}

for (const shell of ["bash", "zsh"]) {
    const output = execSync(
        `docker run --rm -v "${cwd}/src:/pathline/src:ro" -v "${cwd}/tests:/pathline/tests:ro" ${image} ${shell} /pathline/tests/shell-docker.sh`,
        { encoding: "utf-8", timeout: 60_000 },
    )

    const results: TestResult[] = output
        .trim()
        .split("\n")
        .filter((line) => line.startsWith("{"))
        .map((line) => JSON.parse(line))

    describe(`shell tests in ${shell} (Docker)`, () => {
        it("runs every test to completion", () => {
            expect(output.trim().endsWith("DONE")).toBe(true)
        })

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
}
