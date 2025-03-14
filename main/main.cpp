#include <filesystem>
#include <iostream>

int main() {
  std::cout << "Hello, World!" << std::endl;

  std::cout << "Printing current directory:" << std::endl;
  std::cout << std::filesystem::current_path() << std::endl;

  std::cout << "Contents of current directory:" << std::endl;
  for (const auto &entry : std::filesystem::directory_iterator(".")) {
    std::cout << entry.path() << std::endl;
  }
  std::cout << "Done" << std::endl;

  std::cout << "Contents of previous directory:" << std::endl;
  for (const auto &entry : std::filesystem::directory_iterator("..")) {
    std::cout << entry.path() << std::endl;
  }
  std::cout << "Done" << std::endl;

  return 0;
}