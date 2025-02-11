BIN_DIR := build/bin
TEST_DIR := build/test
NAME_SERVER := $(BIN_DIR)/server
NAME_CLIENT := $(BIN_DIR)/client
NAME_SESSION_SENDER := $(TEST_DIR)/session_sender
NAME_MASKED_EXEC := $(TEST_DIR)/masked_exec
NAME_RESPONSE_SERVER := $(TEST_DIR)/response_server
NAME_PARSE_PID_TEST := $(TEST_DIR)/parse_pid_test
NAME_FAULT_SERVER := $(TEST_DIR)/fault_server
NAME_STALE_EXEC := $(TEST_DIR)/stale_exec
NAME_STALE_SERVER_EXEC := $(TEST_DIR)/stale_server_exec
NAME_HIGH_FD_EXEC := $(TEST_DIR)/high_fd_exec

CC := cc
CFLAGS := -Wall -Wextra -Werror -Iinclude -MMD -MP
FAULT_CFLAGS := $(CFLAGS) -DMT_WRITE_CALL=mt_test_write \
	-DMT_EVENT_WRITE=mt_test_event_write -include tests/write_fault.h
OBJ_DIR := build/obj
FAULT_OBJ_DIR := build/fault

SRC := $(wildcard src/*.c)
COMMON_SRC := $(filter-out src/server.c src/client.c,$(SRC))
SERVER_SRC := src/server.c $(COMMON_SRC)
CLIENT_SRC := src/client.c $(COMMON_SRC)
COMMON_OBJ := $(patsubst %.c,$(OBJ_DIR)/%.o,$(COMMON_SRC))
SERVER_OBJ := $(patsubst %.c,$(OBJ_DIR)/%.o,$(SERVER_SRC))
CLIENT_OBJ := $(patsubst %.c,$(OBJ_DIR)/%.o,$(CLIENT_SRC))
SESSION_SENDER_OBJ := $(OBJ_DIR)/tests/session_sender.o $(COMMON_OBJ)
MASKED_EXEC_OBJ := $(OBJ_DIR)/tests/masked_exec.o
RESPONSE_SERVER_OBJ := $(OBJ_DIR)/tests/response_server.o $(COMMON_OBJ)
PARSE_PID_TEST_OBJ := $(OBJ_DIR)/tests/parse_pid_test.o $(OBJ_DIR)/src/parse_pid.o
FAULT_SERVER_OBJ := $(patsubst %.c,$(FAULT_OBJ_DIR)/%.o,$(SERVER_SRC)) \
	$(OBJ_DIR)/tests/write_fault.o
STALE_EXEC_OBJ := $(OBJ_DIR)/tests/stale_exec.o $(COMMON_OBJ)
STALE_SERVER_EXEC_OBJ := $(OBJ_DIR)/tests/stale_server_exec.o $(COMMON_OBJ)
HIGH_FD_EXEC_OBJ := $(OBJ_DIR)/tests/high_fd_exec.o

.PHONY: all clean fclean re test

all: $(NAME_SERVER) $(NAME_CLIENT)

$(NAME_SERVER): $(SERVER_OBJ) | $(BIN_DIR)
	$(CC) $(CFLAGS) $^ -o $@

$(NAME_CLIENT): $(CLIENT_OBJ) | $(BIN_DIR)
	$(CC) $(CFLAGS) $^ -o $@

$(NAME_SESSION_SENDER): $(SESSION_SENDER_OBJ)
	$(CC) $(CFLAGS) $^ -o $@

$(NAME_MASKED_EXEC): $(MASKED_EXEC_OBJ)
	$(CC) $(CFLAGS) $^ -o $@

$(NAME_RESPONSE_SERVER): $(RESPONSE_SERVER_OBJ)
	$(CC) $(CFLAGS) $^ -o $@

$(NAME_PARSE_PID_TEST): $(PARSE_PID_TEST_OBJ)
	$(CC) $(CFLAGS) $^ -o $@

$(NAME_FAULT_SERVER): $(FAULT_SERVER_OBJ)
	$(CC) $(CFLAGS) $^ -o $@

$(NAME_STALE_EXEC): $(STALE_EXEC_OBJ)
	$(CC) $(CFLAGS) $^ -o $@

$(NAME_STALE_SERVER_EXEC): $(STALE_SERVER_EXEC_OBJ)
	$(CC) $(CFLAGS) $^ -o $@

$(NAME_HIGH_FD_EXEC): $(HIGH_FD_EXEC_OBJ)
	$(CC) $(CFLAGS) $^ -o $@

$(NAME_SESSION_SENDER) $(NAME_MASKED_EXEC) $(NAME_RESPONSE_SERVER) \
$(NAME_PARSE_PID_TEST) $(NAME_FAULT_SERVER) $(NAME_STALE_EXEC) \
$(NAME_STALE_SERVER_EXEC) $(NAME_HIGH_FD_EXEC): | $(TEST_DIR)

$(OBJ_DIR)/%.o: %.c include/minitalk.h | $(OBJ_DIR)
	mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c $< -o $@

$(FAULT_OBJ_DIR)/%.o: %.c include/minitalk.h tests/write_fault.h | $(FAULT_OBJ_DIR)
	mkdir -p $(dir $@)
	$(CC) $(FAULT_CFLAGS) -c $< -o $@

$(OBJ_DIR) $(FAULT_OBJ_DIR) $(BIN_DIR) $(TEST_DIR):
	mkdir -p $@

clean:
	rm -rf build

fclean: clean

re: fclean all

test: all $(NAME_SESSION_SENDER) $(NAME_MASKED_EXEC) $(NAME_RESPONSE_SERVER) \
		$(NAME_PARSE_PID_TEST) $(NAME_FAULT_SERVER) $(NAME_STALE_EXEC) \
		$(NAME_STALE_SERVER_EXEC) $(NAME_HIGH_FD_EXEC)
	./$(NAME_PARSE_PID_TEST)
	sh tests/smoke.sh
	sh tests/session_ownership.sh
	sh tests/response_validation.sh
	sh tests/output_failure.sh
	sh tests/protocol_regressions.sh
	sh tests/high_fd.sh
	sh tests/inherited_mask.sh

-include $(SERVER_OBJ:.o=.d) $(CLIENT_OBJ:.o=.d) \
	$(FAULT_SERVER_OBJ:.o=.d)
