// Copyright 2026 Intel Corporation
// Licensed under the Apache License, Version 2.0.

#include <gtest/gtest.h>
#include <openvino/genai/llm_pipeline.hpp>
#include <string>
#include <variant>

#include "src/llm/io_processing/generation_config_builder.hpp"
#include "src/test/platform_utils.hpp"

using namespace ovms;
using Structured = ov::genai::StructuredOutputConfig;

namespace {
const std::string emptySchema = R"({"type":"object","properties":{},"additionalProperties":false})";
const std::string responseSchema = R"({"type":"structural_tag","format":{"type":"json_schema","json_schema":{"type":"object","properties":{"answer":{"type":"string"}}}}})";

OpenAIRequest requestWithTools(const std::string& choice) {
    OpenAIRequest request;
    request.toolChoice = choice;
    request.toolNameSchemaMap.emplace("first", ToolSchemaWrapper{nullptr, emptySchema});
    request.toolNameSchemaMap.emplace("second", ToolSchemaWrapper{nullptr, emptySchema});
    return request;
}

template <typename T>
const T& grammar(const ov::genai::GenerationConfig& config) {
    return *std::get<std::shared_ptr<T>>(std::get<Structured::StructuralTag>(
        config.structured_output_config.value().structural_tags_config.value()));
}
}  // namespace

TEST(Gemma4GenerationContractTest, AbsentToolsAndNonePreserveResponseFormat) {
    for (bool guided : {false, true}) {
        for (bool response : {false, true}) {
            for (bool tools : {false, true}) {
                auto request = tools ? requestWithTools("none") : OpenAIRequest{};
                if (response)
                    request.responseFormat = responseSchema;
                GenerationConfigBuilder builder({}, "gemma4", guided, STANDARD);
                builder.parseConfigFromRequest(request);
                EXPECT_EQ(builder.getConfig().structured_output_config.has_value(), response);
                if (response) {
                    EXPECT_EQ(std::get<std::string>(std::get<Structured::StructuralTag>(
                                  *builder.getConfig().structured_output_config->structural_tags_config)),
                        responseSchema);
                }
            }
        }
    }
}

TEST(Gemma4GenerationContractTest, AutoIsOptionalAndHardChoicesAreImmediateAndRepeatable) {
    for (bool guided : {false, true}) {
        for (const std::string choice : {"auto", "required", "second"}) {
            auto request = requestWithTools(choice);
            GenerationConfigBuilder builder({}, "gemma4", guided, STANDARD);
            builder.parseConfigFromRequest(request);
            if (choice == "auto" && !guided) {
                EXPECT_FALSE(builder.getConfig().structured_output_config);
            } else if (choice == "auto") {
                const auto& tags = grammar<Structured::TriggeredTags>(builder.getConfig());
                EXPECT_FALSE(tags.at_least_one);
                EXPECT_FALSE(tags.stop_after_first);
                EXPECT_EQ(tags.triggers, std::vector<std::string>{"<|tool_call>"});
                ASSERT_EQ(tags.tags.size(), 2u);
            } else {
                const auto& tags = grammar<Structured::TagsWithSeparator>(builder.getConfig());
                EXPECT_TRUE(tags.at_least_one);
                EXPECT_FALSE(tags.stop_after_first);
                EXPECT_TRUE(tags.separator.empty());
                ASSERT_EQ(tags.tags.size(), choice == "second" ? 1u : 2u);
                if (choice == "second")
                    EXPECT_EQ(tags.tags[0].begin, "<|tool_call>call:second");
            }
        }
    }
}

TEST(Gemma4GenerationContractTest, ImpossibleHardChoiceIsRejected) {
    for (bool guided : {false, true}) {
        for (const std::string choice : {"required", "missing"}) {
            OpenAIRequest request;
            request.toolChoice = choice;
            GenerationConfigBuilder builder({}, "gemma4", guided, STANDARD);
            EXPECT_THROW(builder.parseConfigFromRequest(request), std::invalid_argument);
        }
        auto request = requestWithTools("missing");
        GenerationConfigBuilder builder({}, "gemma4", guided, STANDARD);
        EXPECT_THROW(builder.parseConfigFromRequest(request), std::invalid_argument);
    }
}

TEST(Gemma4GenerationContractTest, ResponseFormatAndActiveToolsCannotSilentlyReplaceConstraints) {
    for (bool guided : {false, true}) {
        for (const std::string choice : {"auto", "required", "second"}) {
            auto request = requestWithTools(choice);
            request.responseFormat = responseSchema;
            GenerationConfigBuilder builder({}, "gemma4", guided, STANDARD);
            EXPECT_THROW(builder.parseConfigFromRequest(request), std::invalid_argument);
        }
    }
}

TEST(Gemma4GenerationContractTest, GuidedSchemaMustDescribeAnObject) {
    for (const std::string schema : {R"({"type":"array","items":{"type":"integer"}})",
             R"({"type":"string"})", "invalid"}) {
        auto request = requestWithTools("required");
        request.toolNameSchemaMap["first"].stringRepr = schema;
        GenerationConfigBuilder builder({}, "gemma4", true, STANDARD);
        EXPECT_THROW(builder.parseConfigFromRequest(request), std::invalid_argument);
    }
}

TEST(Gemma4GenerationContractTest, ObjectSchemaIsPassedWithoutLosingNestedConstraints) {
    const std::string schema = R"({"type":"object","properties":{"nested":{"type":"object","properties":{"x":{"enum":[1,2]}}},"array":{"type":"array","items":{"type":["number","boolean","null"]}},"optional":{"type":"string"}},"required":["nested"],"additionalProperties":false})";
    auto request = requestWithTools("first");
    request.toolNameSchemaMap.erase("second");
    request.toolNameSchemaMap["first"].stringRepr = schema;
    GenerationConfigBuilder builder({}, "gemma4", false, STANDARD);
    builder.parseConfigFromRequest(request);
    const auto& tags = grammar<Structured::TagsWithSeparator>(builder.getConfig());
    ASSERT_EQ(tags.tags.size(), 1u);
    EXPECT_EQ(std::get<Structured::JSONSchema>(tags.tags[0].content).value, schema);
    ov::genai::Tokenizer tokenizer(getGenericFullPathForSrcTest("/ovms/src/test/llm_testing/facebook/opt-125m"));
    EXPECT_NO_THROW(builder.validateStructuredOutputConfig(tokenizer));
}

TEST(Gemma4GenerationContractTest, SamplingAndStopLimitsSurviveToolGrammar) {
    for (float temperature : {0.f, 0.7f}) {
        auto request = requestWithTools("required");
        request.temperature = temperature;
        request.topK = 17;
        request.topP = .8f;
        request.maxTokens = 23;
        request.stop = std::set<std::string>{"STOP"};
        GenerationConfigBuilder builder({}, "gemma4", false, STANDARD);
        builder.parseConfigFromRequest(request);
        builder.adjustConfigForDecodingMethod();
        const auto& config = builder.getConfig();
        EXPECT_EQ(config.do_sample, temperature > 0);
        EXPECT_FLOAT_EQ(config.temperature, temperature);
        EXPECT_EQ(config.top_k, 17u);
        EXPECT_FLOAT_EQ(config.top_p, .8f);
        EXPECT_EQ(config.max_new_tokens, 23u);
        EXPECT_EQ(config.stop_strings, *request.stop);
    }
}

// Exercises the real 2026.4 grammar with a small CPU model whose marker encoding
// is fragmented. This is grammar evidence, not Gemma4 model/GPU acceptance.
TEST(Gemma4GenerationContractTest, GenAiHardChoiceHasNoProsePrefixWithFragmentedTokenizer) {
    const auto path = getGenericFullPathForSrcTest("/ovms/src/test/llm_testing/facebook/opt-125m");
    ov::genai::LLMPipeline pipeline(path, "CPU");
    auto tokenizer = pipeline.get_tokenizer();
    auto encoded = tokenizer.encode("<|tool_call>", ov::genai::add_special_tokens(false)).input_ids;
    ASSERT_GT(encoded.get_size(), 1u);
    auto request = requestWithTools("first");
    request.toolNameSchemaMap.erase("second");
    request.temperature = 0.f;
    request.maxTokens = 40;
    GenerationConfigBuilder builder(pipeline.get_generation_config(), "gemma4", false, STANDARD);
    builder.parseConfigFromRequest(request);
    ASSERT_NO_THROW(builder.validateStructuredOutputConfig(tokenizer));
    auto result = pipeline.generate("Write a normal greeting.", builder.getConfig());
    ASSERT_EQ(result.texts.size(), 1u);
    EXPECT_EQ(result.texts[0].find("<|tool_call>call:first"), 0u) << result.texts[0];
    EXPECT_NE(result.texts[0].find("{}<tool_call|>"), std::string::npos) << result.texts[0];
}
