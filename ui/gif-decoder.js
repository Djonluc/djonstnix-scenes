(() => {
    function readString(bytes, start, length) {
        let value = '';
        for (let i = 0; i < length; i += 1) {
            value += String.fromCharCode(bytes[start + i] || 0);
        }
        return value;
    }

    class Stream {
        constructor(buffer) {
            this.bytes = new Uint8Array(buffer);
            this.offset = 0;
        }

        readByte() {
            if (this.offset >= this.bytes.length) {
                throw new Error('Unexpected end of GIF data');
            }

            return this.bytes[this.offset++];
        }

        readUint16() {
            const low = this.readByte();
            const high = this.readByte();
            return low | (high << 8);
        }

        readBytes(length) {
            const start = this.offset;
            this.offset += length;
            if (this.offset > this.bytes.length) {
                throw new Error('Unexpected end of GIF data');
            }

            return this.bytes.subarray(start, start + length);
        }
    }

    function readColorTable(stream, colorCount) {
        const table = new Array(colorCount);
        for (let i = 0; i < colorCount; i += 1) {
            table[i] = [
                stream.readByte(),
                stream.readByte(),
                stream.readByte(),
            ];
        }
        return table;
    }

    function readSubBlocks(stream) {
        const chunks = [];
        let totalLength = 0;

        while (true) {
            const blockSize = stream.readByte();
            if (blockSize === 0) {
                break;
            }

            const chunk = stream.readBytes(blockSize);
            chunks.push(chunk);
            totalLength += chunk.length;
        }

        const merged = new Uint8Array(totalLength);
        let offset = 0;
        for (const chunk of chunks) {
            merged.set(chunk, offset);
            offset += chunk.length;
        }

        return merged;
    }

    function lzwDecode(minCodeSize, data, pixelCount) {
        const clearCode = 1 << minCodeSize;
        const endCode = clearCode + 1;

        let codeSize = minCodeSize + 1;
        let bitIndex = 0;
        let nextCode = endCode + 1;
        let dictionary = [];
        let previous = null;
        const output = [];

        function resetDictionary() {
            dictionary = [];
            for (let i = 0; i < clearCode; i += 1) {
                dictionary[i] = [i];
            }
            dictionary[clearCode] = null;
            dictionary[endCode] = null;
            codeSize = minCodeSize + 1;
            nextCode = endCode + 1;
            previous = null;
        }

        function readCode() {
            let code = 0;
            for (let i = 0; i < codeSize; i += 1) {
                const byteIndex = bitIndex >> 3;
                const shift = bitIndex & 7;
                const bit = ((data[byteIndex] || 0) >> shift) & 1;
                code |= bit << i;
                bitIndex += 1;
            }
            return code;
        }

        resetDictionary();

        while (output.length < pixelCount && bitIndex < data.length * 8) {
            const code = readCode();

            if (code === clearCode) {
                resetDictionary();
                continue;
            }

            if (code === endCode) {
                break;
            }

            let entry = dictionary[code];
            if (!entry) {
                if (!previous) {
                    break;
                }
                entry = previous.concat(previous[0]);
            }

            for (let i = 0; i < entry.length && output.length < pixelCount; i += 1) {
                output.push(entry[i]);
            }

            if (previous) {
                dictionary[nextCode] = previous.concat(entry[0]);
                nextCode += 1;

                if (nextCode === (1 << codeSize) && codeSize < 12) {
                    codeSize += 1;
                }
            }

            previous = entry;
        }

        return new Uint8Array(output);
    }

    function deinterlace(indices, width, height) {
        const result = new Uint8Array(width * height);
        const passes = [
            { start: 0, step: 8 },
            { start: 4, step: 8 },
            { start: 2, step: 4 },
            { start: 1, step: 2 },
        ];

        let offset = 0;
        for (const pass of passes) {
            for (let y = pass.start; y < height; y += pass.step) {
                result.set(indices.subarray(offset, offset + width), y * width);
                offset += width;
            }
        }

        return result;
    }

    function clearFrameRect(pixels, canvasWidth, left, top, width, height) {
        for (let y = 0; y < height; y += 1) {
            const rowStart = ((top + y) * canvasWidth + left) * 4;
            pixels.fill(0, rowStart, rowStart + (width * 4));
        }
    }

    function renderFramePixels(target, canvasWidth, left, top, width, height, indices, colorTable, transparentIndex) {
        if (!colorTable) {
            return;
        }

        let sourceIndex = 0;
        for (let y = 0; y < height; y += 1) {
            const rowOffset = ((top + y) * canvasWidth + left) * 4;
            for (let x = 0; x < width; x += 1) {
                const colorIndex = indices[sourceIndex++];
                if (colorIndex === transparentIndex) {
                    continue;
                }

                const color = colorTable[colorIndex];
                if (!color) {
                    continue;
                }

                const targetIndex = rowOffset + (x * 4);
                target[targetIndex] = color[0];
                target[targetIndex + 1] = color[1];
                target[targetIndex + 2] = color[2];
                target[targetIndex + 3] = 255;
            }
        }
    }

    function parse(buffer) {
        const stream = new Stream(buffer);
        const header = readString(stream.bytes, 0, 6);
        if (header !== 'GIF87a' && header !== 'GIF89a') {
            throw new Error('Invalid GIF header');
        }

        stream.offset = 6;

        const width = stream.readUint16();
        const height = stream.readUint16();
        const packed = stream.readByte();
        const hasGlobalColorTable = (packed & 0x80) !== 0;
        const globalColorTableSize = 1 << ((packed & 0x07) + 1);
        const backgroundColorIndex = stream.readByte();
        stream.readByte();

        const globalColorTable = hasGlobalColorTable ? readColorTable(stream, globalColorTableSize) : null;

        const backgroundColor = globalColorTable && globalColorTable[backgroundColorIndex]
            ? globalColorTable[backgroundColorIndex]
            : null;

        const basePixels = new Uint8ClampedArray(width * height * 4);
        const frames = [];
        let loopCount = 0;
        let graphicsControl = {
            delayMs: 100,
            transparentIndex: null,
            disposal: 0,
        };

        while (stream.offset < stream.bytes.length) {
            const blockId = stream.readByte();

            if (blockId === 0x3B) {
                break;
            }

            if (blockId === 0x21) {
                const extensionId = stream.readByte();

                if (extensionId === 0xF9) {
                    stream.readByte();
                    const gcePacked = stream.readByte();
                    const delay = stream.readUint16();
                    const transparentIndex = stream.readByte();
                    stream.readByte();

                    graphicsControl = {
                        delayMs: Math.max(20, (delay || 10) * 10),
                        transparentIndex: (gcePacked & 0x01) !== 0 ? transparentIndex : null,
                        disposal: (gcePacked >> 2) & 0x07,
                    };
                    continue;
                }

                if (extensionId === 0xFF) {
                    const blockSize = stream.readByte();
                    const appIdentifier = readString(stream.readBytes(blockSize), 0, blockSize);
                    const appData = readSubBlocks(stream);
                    if ((appIdentifier === 'NETSCAPE2.0' || appIdentifier === 'ANIMEXTS1.0') && appData.length >= 3 && appData[0] === 1) {
                        loopCount = appData[1] | (appData[2] << 8);
                    }
                    continue;
                }

                readSubBlocks(stream);
                continue;
            }

            if (blockId !== 0x2C) {
                throw new Error('Unsupported GIF block');
            }

            const left = stream.readUint16();
            const top = stream.readUint16();
            const frameWidth = stream.readUint16();
            const frameHeight = stream.readUint16();
            const imagePacked = stream.readByte();
            const hasLocalColorTable = (imagePacked & 0x80) !== 0;
            const isInterlaced = (imagePacked & 0x40) !== 0;
            const localColorTableSize = 1 << ((imagePacked & 0x07) + 1);
            const colorTable = hasLocalColorTable ? readColorTable(stream, localColorTableSize) : globalColorTable;
            const minCodeSize = stream.readByte();
            const imageData = readSubBlocks(stream);

            let colorIndices = lzwDecode(minCodeSize, imageData, frameWidth * frameHeight);
            if (isInterlaced) {
                colorIndices = deinterlace(colorIndices, frameWidth, frameHeight);
            }

            const previousPixels = graphicsControl.disposal === 3 ? new Uint8ClampedArray(basePixels) : null;
            const compositedPixels = new Uint8ClampedArray(basePixels);

            renderFramePixels(
                compositedPixels,
                width,
                left,
                top,
                frameWidth,
                frameHeight,
                colorIndices,
                colorTable,
                graphicsControl.transparentIndex
            );

            frames.push({
                delayMs: graphicsControl.delayMs,
                width,
                height,
                pixels: compositedPixels,
            });

            if (graphicsControl.disposal === 2) {
                basePixels.set(compositedPixels);
                clearFrameRect(basePixels, width, left, top, frameWidth, frameHeight);

                // Modified: Only fill with opaque background color if NO transparency is defined.
                // Standard behavior for transparent GIFs is to restore the area to fully transparent.
                if (backgroundColor && graphicsControl.transparentIndex === null) {
                    for (let y = 0; y < frameHeight; y += 1) {
                        for (let x = 0; x < frameWidth; x += 1) {
                            const pixelIndex = (((top + y) * width) + left + x) * 4;
                            basePixels[pixelIndex] = backgroundColor[0];
                            basePixels[pixelIndex + 1] = backgroundColor[1];
                            basePixels[pixelIndex + 2] = backgroundColor[2];
                            basePixels[pixelIndex + 3] = 255;
                        }
                    }
                }
            } else if (graphicsControl.disposal === 3 && previousPixels) {
                basePixels.set(previousPixels);
            } else {
                basePixels.set(compositedPixels);
            }

            graphicsControl = {
                delayMs: 100,
                transparentIndex: null,
                disposal: 0,
            };
        }

        return {
            width,
            height,
            loopCount,
            frames,
        };
    }

    window.GifDecoder = {
        parse,
    };
})();
