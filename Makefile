SHELL := /bin/bash

# Debug configuration
ifeq ($(DEBUG),1)
    MAKEFLAGS += --no-print-directory
    MAKEFLAGS += --keep-going
    MAKEFLAGS += --ignore-errors
    .SHELLFLAGS = -x -c
endif

# Default goal
.DEFAULT_GOAL := help

# Deployment configuration
DEPLOYMENT_NAME ?= instructlab
IMAGE_NAME ?= redhat/instructlab
IMAGE_TAG ?= latest
CONFIG_MAP_NAME ?= instructlab-config

.PHONY: help
help:
	@echo "InstructLab Management System"
	@echo ""
	@echo "Available targets:"
	@echo ""
	@echo "Deployment:"
	@echo "  deploy              - Deploy InstructLab with ConfigMap"
	@echo "  undeploy            - Remove InstructLab deployment"
	@echo ""
	@echo "Interaction:"
	@echo "  logs                - View container logs"
	@echo "  status              - Show deployment status"
	@echo ""
	@echo "Utility:"
	@echo "  help                - Show this help message"

define CONFIG_MAP
apiVersion: v1
kind: ConfigMap
metadata:
  name: $(CONFIG_MAP_NAME)
data:
  config.yaml: |
    chat:
      context: default
      greedy_mode: false
      logs_dir: data/chatlogs
      max_tokens: null
      model: models/merlinite-7b-lab-Q4_K_M.gguf
      session: null
      vi_mode: false
      visible_overflow: true

    general:
      log_level: INFO
      debug_level: 0

    generate:
      chunk_word_count: 1000
      model: models/merlinite-7b-lab-Q4_K_M.gguf
      num_cpus: 10
      num_instructions: 100
      output_dir: data/generated
      prompt_file: prompts.yaml
      seed_file: seeds.yaml
      taxonomy_base: origin/main
      taxonomy_path: taxonomy

    serve:
      backend: vllm
      chat_template: auto
      host_port: 0.0.0.0:8000
      model_path: models/merlinite-7b-lab-Q4_K_M.gguf
      llama_cpp:
        gpu_layers: -1
        llm_family: ''
        max_ctx_size: 4096
      vllm:
        llm_family: ''
        vllm_args: ["--tensor-parallel-size", "1"]
        gpus: 1

    evaluate:
      base_model: models/merlinite-7b-lab-Q4_K_M.gguf
      gpus: 1
      mmlu:
        batch_size: 16
        few_shots: 5
      mmlu_branch:
        tasks_dir: benchmarks/mmlu
      mt_bench:
        judge_model: gpt-4
        max_workers: 4
        output_dir: benchmarks/mt_bench
      mt_bench_branch:
        taxonomy_path: taxonomy

    train:
      model_path: models/merlinite-7b-lab-Q4_K_M.gguf
      data_path: data/generated
      data_output_dir: data/train_output
      ckpt_output_dir: checkpoints
      num_epochs: 3
      effective_batch_size: 64
      lora_rank: 8
      lora_quantize_dtype: bf16
      nproc_per_node: 1
      max_seq_len: 4096
      max_batch_len: 1024
      is_padding_free: true
      deepspeed_cpu_offload_optimizer: true
      save_samples: 100
      additional_args: {}
endef
export CONFIG_MAP

define DEPLOYMENT
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $(DEPLOYMENT_NAME)
spec:
  replicas: 1
  selector:
    matchLabels:
      app: instructlab
  template:
    metadata:
      labels:
        app: instructlab
    spec:
      containers:
        - name: instructlab
          image: $(IMAGE_NAME):$(IMAGE_TAG)
          imagePullPolicy: Always
          command: ["ilab", "--config", "/app/config.yaml", "generate"]
          volumeMounts:
            - name: config-volume
              mountPath: /app/config.yaml
              subPath: config.yaml
      volumes:
        - name: config-volume
          configMap:
            name: $(CONFIG_MAP_NAME)
endef
export DEPLOYMENT

.PHONY: create-configmap
create-configmap:
	@echo "Creating ConfigMap..."
	@echo "$$CONFIG_MAP" | kubectl apply -f -

.PHONY: deploy
deploy: create-configmap
	@echo "Deploying InstructLab..."
	@echo "$$DEPLOYMENT" | kubectl apply -f -
	@echo "Deployment complete"

.PHONY: undeploy
undeploy:
	@echo "Removing InstructLab deployment..."
	@-kubectl delete deployment $(DEPLOYMENT_NAME) 2>/dev/null || true
	@-kubectl delete configmap $(CONFIG_MAP_NAME) 2>/dev/null || true
	@echo "Undeployment complete"

.PHONY: status
status:
	@echo "Deployment status:"
	@kubectl get deployment/$(DEPLOYMENT_NAME) -o wide
	@echo ""
	@echo "Pod status:"
	@kubectl get pods -l app=instructlab

.PHONY: logs
logs:
	@echo "Showing logs for latest pod:"
	@kubectl logs $$(kubectl get pods -l app=instructlab -o jsonpath='{.items[0].metadata.name}') --tail=100 -f

.PHONY: get-pod-name
get-pod-name:
	@PODS=$$(kubectl get pods -l app=instructlab -o jsonpath='{.items[*].metadata.name}'); \
    if [ -z "$$PODS" ]; then \
        echo "Error: No InstructLab pods found."; \
        exit 1; \
    fi; \
    echo "$$PODS" | awk '{print $$1}'
