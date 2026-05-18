build:
    odin build src -out:camp

build-e2e:
    odin build src/e2e -out:camp-e2e

test-unit:
    odin test src

test-e2e: build build-e2e
    CAMP_BIN="$(pwd)/camp" ./camp-e2e

test: test-unit test-e2e

update-snapshots: build build-e2e
    CAMP_BIN="$(pwd)/camp" ./camp-e2e --update

test-filter pattern: build build-e2e
    CAMP_BIN="$(pwd)/camp" ./camp-e2e --filter {{pattern}}
