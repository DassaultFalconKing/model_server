//*****************************************************************************
// Copyright 2026 Intel Corporation
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//*****************************************************************************

#include <gtest/gtest.h>
#include <openvino/genai/tokenizer.hpp>
#include <rapidjson/document.h>

#include <cstdlib>
#include <memory>
#include <string>
#include <utility>
#include <variant>
#include <vector>

#include "../../../llm/io_processing/output_parser.hpp"
#include "../../../llm/io_processing/gemma4/gemma4_tool_parser.hpp"
#include "../../platform_utils.hpp"

using namespace ovms;

#ifdef _WIN32
const std::string hardeningTokenizerPath = getWindowsRepoRootPath() + "\\src\\test\\llm_testing\\OpenVINO\\gemma-4-E4B-it-int4-ov";
#else
const std::string hardeningTokenizerPath = "/ovms/src/test/llm_testing/OpenVINO/gemma-4-E4B-it-int4-ov";
#endif

namespace {
const std::string questionSchema = R"({"type":"object","properties":{"value":{},"path":{"type":"string"},"text":{"type":"string"}}})";

struct ParsedDirect {
    std::string content;
    std::vector<ToolCallDelta> toolCalls;
};

class Gemma4ParserHardeningTest : public ::testing::Test {
protected:
    static std::unique_ptr<ov::genai::Tokenizer> tokenizer;

    static void SetUpTestSuite() {
        const char* configured = std::getenv("GEMMA4_TOKENIZER_PATH");
        tokenizer = std::make_unique<ov::genai::Tokenizer>(configured ? configured : hardeningTokenizerPath);
    }

    static void TearDownTestSuite() {
        tokenizer.reset();
    }

    static ToolsSchemas_t questionTools() {
        ToolsSchemas_t tools;
        tools.emplace("question", ToolSchemaWrapper{nullptr, questionSchema});
        return tools;
    }

    static void collectDelta(ParsedDirect& parsed, const std::optional<Delta>& delta) {
        if (!delta.has_value())
            return;
        std::visit([&](const auto& value) {
            using T = std::decay_t<decltype(value)>;
            if constexpr (std::is_same_v<T, ContentDelta>) {
                parsed.content.append(value.text);
            } else if constexpr (std::is_same_v<T, ToolCallDelta>) {
                parsed.toolCalls.push_back(value);
            }
        }, *delta);
    }

    ParsedDirect parseChunks(const std::vector<std::string>& chunks) {
        Gemma4ToolParser parser(*tokenizer, questionTools());
        ParsedDirect parsed;
        for (const auto& chunk : chunks) {
            for (int phase = 0; phase < 12; ++phase) {
                auto delta = parser.parseChunk(phase == 0 ? chunk : "", {}, ov::genai::GenerationFinishReason::NONE);
                collectDelta(parsed, delta);
            }
        }
        for (int phase = 0; phase < 12; ++phase) {
            auto delta = parser.parseChunk("", {}, ov::genai::GenerationFinishReason::STOP);
            collectDelta(parsed, delta);
        }
        return parsed;
    }

    rapidjson::Document parseArgumentsObject(const std::string& arguments) {
        rapidjson::Document doc;
        doc.Parse(arguments.c_str());
        EXPECT_FALSE(doc.HasParseError()) << arguments;
        EXPECT_TRUE(doc.IsObject()) << arguments;
        return doc;
    }
};

std::unique_ptr<ov::genai::Tokenizer> Gemma4ParserHardeningTest::tokenizer;
}  // namespace

TEST_F(Gemma4ParserHardeningTest, PreservesWindowsPathArgumentsByteForByte) {
    struct Case {
        std::string input;
        std::string expected;
    };
    const std::vector<Case> cases{
        {R"(<|tool_call>call:question{path:<|"|>C:\git\g4-final-review<|"|>}<tool_call|>)", R"(C:\git\g4-final-review)"},
        {R"(<|tool_call>call:question{"path":"C:\\git\\g4-final-review"}<tool_call|>)", R"(C:\git\g4-final-review)"},
        {R"(<|tool_call>call:question{path:<|"|>C:/git/g4-final-review<|"|>}<tool_call|>)", "C:/git/g4-final-review"},
    };

    for (const auto& testCase : cases) {
        SCOPED_TRACE(testCase.input);
        auto parsed = parseChunks({testCase.input});
        ASSERT_EQ(parsed.toolCalls.size(), 1u);
        ASSERT_TRUE(parsed.toolCalls[0].name.has_value());
        EXPECT_EQ(parsed.toolCalls[0].name.value(), "question");
        auto doc = parseArgumentsObject(parsed.toolCalls[0].arguments);
        ASSERT_TRUE(doc.HasMember("path"));
        ASSERT_TRUE(doc["path"].IsString());
        EXPECT_EQ(std::string(doc["path"].GetString(), doc["path"].GetStringLength()), testCase.expected);
    }
}
