#ifndef INCLUDE_git_blob_h__
#define INCLUDE_git_blob_h__

#include "common.h"
#include "types.h"

GIT_BEGIN_DECL

/**
 * Perform a cherry-pick
 *
 * @param input dummy input
 * @returns the usual
 */
GIT_EXTERN(int) git_cherrypick(char *input);

GIT_END_DECL
