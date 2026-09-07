// Copyright 2026 Intel Corporation
// Licensed under the Apache License, Version 2.0.

#include <chrono>
#include <memory>
#include <optional>
#include <string>

#include <gtest/gtest.h>
#include <openvino/genai/tokenizer.hpp>

#include "src/llm/apis/openai_completions.hpp"
#include "src/test/platform_utils.hpp"

using namespace ovms;

namespace {

std::string requestJson(const std::string& parallelField) {
    return std::string(R"({
        "model": "gemma4",
        "messages": [{"role": "user", "content": "Use tools if needed"}],
        "tools": [{
            "type": "function",
            "function": {
                "name": "first",
                "parameters": {"type": "object", "properties": {}, "additionalProperties": false}
            }
        }])") + parallelField + "}";
}

struct ParsedParallelPolicy {
    absl::Status status;
    bool parallelToolCalls{true};
};

ParsedParallelPolicy parseParallelPolicy(const std::string& parallelField) {
    rapidjson::Document doc;
    const std::string json = requestJson(parallelField);
    doc.Parse(json.c_str());
    if (doc.HasParseError()) {
        return {absl::InvalidArgumentError("test JSON failed to parse"), true};
    }

    ov::genai::Tokenizer tokenizer(getGenericFullPathForSrcTest(
        "/ovms/src/test/llm_testing/facebook/opt-125m"));
    OpenAIChatCompletionsHandler handler(
        doc,
        Endpoint::CHAT_COMPLETIONS,
        std::chrono::system_clock::now(),
        tokenizer);

    auto status = handler.parseRequest(
        /*maxTokensLimit=*/std::nullopt,
        /*bestOfLimit=*/0,
        /*maxModelLength=*/std::nullopt);
    return {status, handler.getRequest().parallelToolCalls};
}

}  // namespace

TEST(OpenAIParallelToolCallsContractTest, DefaultsToEnabledWhenFieldIsAbsent) {
    const auto result = parseParallelPolicy("");
    ASSERT_TRUE(result.status.ok()) << result.status;
    EXPECT_TRUE(result.parallelToolCalls);
}

TEST(OpenAIParallelToolCallsContractTest, ParsesExplicitBooleanPolicy) {
    const auto enabled = parseParallelPolicy(", \"parallel_tool_calls\": true");
    ASSERT_TRUE(enabled.status.ok()) << enabled.status;
    EXPECT_TRUE(enabled.parallelToolCalls);

    const auto disabled = parseParallelPolicy(", \"parallel_tool_calls\": false");
    ASSERT_TRUE(disabled.status.ok()) << disabled.status;
    EXPECT_FALSE(disabled.parallelToolCalls);
}

TEST(OpenAIParallelToolCallsContractTest, RejectsNonBooleanValues) {
    for (const std::string value : {"1", "\"no\"", "[]", "{}"}) {
        SCOPED_TRACE(value);
        const auto result = parseParallelPolicy(", \"parallel_tool_calls\": " + value);
        EXPECT_FALSE(result.status.ok());
        EXPECT_EQ(result.status.code(), absl::StatusCode::kInvalidArgument);
    }
}
