/*
 * This file is to create a function which takes a callback in order
 * to test that we detect it correctly and will write it out.
 */

#include "common.h"

/**
 * Worker which does soemthing to its pointer
 */
typedef int (*git_callback_do_work)(int *foo);

/**
 * Schedule some work to happen for a particular function
 */
GIT_EXTERN(int) git_work_schedule(git_callback_do_work worker);
