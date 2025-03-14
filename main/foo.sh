#!/bin/bash

echo $RUNFILES_DIR
echo $BASH_SOURCE
ls ..
ls ../+_repo_rules+hello-in-module
ls
ls main

# # Access hello.txt directly, as Bazel places it in the runfiles directory
# # which is the current working directory when the sh_binary is executed.
# content=$(cat hello.txt)

# echo "Content of hello.txt:"
# echo "$content"

# # Example: Using the content in a simple conditional
# if [[ "$content" == *"Hello"* ]]; then
#   echo "hello.txt contains the word 'Hello'."
# else
#   echo "hello.txt does not contain the word 'Hello'."
# fi

# # Example: Using the content as an argument to another command
# grep "example" hello.txt

# Example: Using hello.txt as an input to a program called my_program
# ./my_program < hello.txt

# Example: If you needed to find the actual path to the runfiles directory
# (though it's usually not necessary), you could use $0 to get the path
# to the script, and then use dirname to get the directory.
# runfiles_dir=$(dirname "$0")
# content2=$(cat "$runfiles_dir/hello.txt")
# echo "Content using runfiles_dir: $content2"

# Example: if you have multiple data dependencies, they will all be in the same directory.
# content_datafiles_txt=$(cat datafiles/local_file.txt)
# echo "Content from local_file.txt: $content_datafiles_txt"