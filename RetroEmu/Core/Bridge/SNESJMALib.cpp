// SNESJMALib.cpp
// JMA 压缩库 + load_jma_file 完整实现
//
// 本文件不 include snes9x 头文件，用字面量替代 CMemory::MAX_ROM_SIZE
//（= 0xC00000，见 Snes9x/memmap.h），彻底避免头文件冲突。

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-variable"
#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wshadow"

// JMA 库核心（纯 C++，不依赖 snes9x）
#include "../../../Snes9x/jma/7zlzma.cpp"
#include "../../../Snes9x/jma/crc32.cpp"
#include "../../../Snes9x/jma/iiostrm.cpp"
#include "../../../Snes9x/jma/inbyte.cpp"
#include "../../../Snes9x/jma/jma.cpp"
#include "../../../Snes9x/jma/lzma.cpp"
#include "../../../Snes9x/jma/lzmadec.cpp"
#include "../../../Snes9x/jma/winout.cpp"

#pragma clang diagnostic pop

// ── load_jma_file ────────────────────────────────────────────────────────────
// 不 include snes9x.h / memmap.h，用字面量替代 CMemory::MAX_ROM_SIZE

#include "../../../Snes9x/jma/s9x-jma.h"
#include "../../../Snes9x/jma/jma.h"
#include <string>
#include <vector>

static const size_t SNES_MAX_ROM_SIZE = 0xC00000; // CMemory::MAX_ROM_SIZE

size_t load_jma_file(const char *filename, unsigned char *buffer)
{
    try
    {
        JMA::jma_open JMAFile(filename);
        std::vector<JMA::jma_public_file_info> file_info = JMAFile.get_files_info();

        std::string our_file_name;
        size_t our_file_size = 0;

        for (std::vector<JMA::jma_public_file_info>::iterator i = file_info.begin();
             i != file_info.end(); ++i)
        {
            if ((i->size <= SNES_MAX_ROM_SIZE + 512) && (i->size > our_file_size))
            {
                our_file_name = i->name;
                our_file_size = i->size;
            }
        }

        if (!our_file_size)
            return 0;

        JMAFile.extract_file(our_file_name, buffer);
        return our_file_size;
    }
    catch (JMA::jma_errors)
    {
        return 0;
    }
}
