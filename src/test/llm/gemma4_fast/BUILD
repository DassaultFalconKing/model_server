load("//:common_settings.bzl", "COMMON_LOCAL_DEFINES", "COMMON_STATIC_LIBS_LINKOPTS", "COPTS_TESTS")

cc_test(
    name = "gemma4_parser_contract_test",
    srcs = ["gemma4_parser_contract_test.cpp"],
    deps = [
        "@com_google_googletest//:gtest_main",
        "//src:test_platform_utils",
        "//src/llm:output_parsers",
        "//src/llm:text_streamer",
        "//third_party:genai",
    ],
    copts = COPTS_TESTS,
    local_defines = COMMON_LOCAL_DEFINES,
    linkopts = COMMON_STATIC_LIBS_LINKOPTS,
    linkstatic = 1,
)
