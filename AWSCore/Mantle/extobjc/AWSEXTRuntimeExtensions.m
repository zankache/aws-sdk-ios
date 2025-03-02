//
//  EXTRuntimeExtensions.m
//  extobjc
//
//  Created by Justin Spahr-Summers on 2011-03-05.
//  Copyright (C) 2012 Justin Spahr-Summers.
//  Released under the MIT license.
//

#import "AWSEXTRuntimeExtensions.h"

#import <Foundation/Foundation.h>

awsmtl_propertyAttributes *awsmtl_copyPropertyAttributes (objc_property_t property) {
    const char * const attrString = property_getAttributes(property);
    if (!attrString) {
        return NULL;
    }

    if (attrString[0] != 'T') {
        return NULL;
    }

    const char *typeString = attrString + 1;
    const char *next = NSGetSizeAndAlignment(typeString, NULL, NULL);
    if (!next) {
        return NULL;
    }

    size_t typeLength = next - typeString;
    if (!typeLength) {
        return NULL;
    }

    // allocate enough space for the structure and the type string (plus a NUL)
    awsmtl_propertyAttributes *attributes = calloc(1, sizeof(awsmtl_propertyAttributes) + typeLength + 1);
    if (!attributes) {
        return NULL;
    }

    // copy the type string
    strncpy(attributes->type, typeString, typeLength);
    attributes->type[typeLength] = '\0';

    // if this is an object type, and immediately followed by a quoted string...
    if (typeString[0] == *(@encode(id)) && typeString[1] == '"') {
        // we should be able to extract a class name
        const char *className = typeString + 2;
        next = strchr(className, '"');

        if (!next) {
            return NULL;
        }

        if (className != next) {
            size_t classNameLength = next - className;
            char trimmedName[classNameLength + 1];

            strncpy(trimmedName, className, classNameLength);
            trimmedName[classNameLength] = '\0';

            // attempt to look up the class in the runtime
            attributes->objectClass = objc_getClass(trimmedName);
        }
    }

    if (*next != '\0') {
        // skip past any junk before the first flag
        next = strchr(next, ',');
    }

    while (next && *next == ',') {
        char flag = next[1];
        next += 2;

        switch (flag) {
        case '\0':
            break;

        case 'R':
            attributes->readonly = YES;
            break;

        case 'C':
            attributes->memoryManagementPolicy = awsmtl_propertyMemoryManagementPolicyCopy;
            break;

        case '&':
            attributes->memoryManagementPolicy = awsmtl_propertyMemoryManagementPolicyRetain;
            break;

        case 'N':
            attributes->nonatomic = YES;
            break;

        case 'G':
        case 'S':
            {
                const char *nextFlag = strchr(next, ',');
                SEL name = NULL;

                if (!nextFlag) {
                    // assume that the rest of the string is the selector
                    const char *selectorString = next;
                    next = "";

                    name = sel_registerName(selectorString);
                } else {
                    size_t selectorLength = nextFlag - next;
                    if (!selectorLength) {
                        goto errorOut;
                    }

                    char selectorString[selectorLength + 1];

                    strncpy(selectorString, next, selectorLength);
                    selectorString[selectorLength] = '\0';

                    name = sel_registerName(selectorString);
                    next = nextFlag;
                }

                if (flag == 'G')
                    attributes->getter = name;
                else
                    attributes->setter = name;
            }

            break;

        case 'D':
            attributes->dynamic = YES;
            attributes->ivar = NULL;
            break;

        case 'V':
            // assume that the rest of the string (if present) is the ivar name
            if (*next == '\0') {
                // if there's nothing there, let's assume this is dynamic
                attributes->ivar = NULL;
            } else {
                attributes->ivar = next;
                next = "";
            }

            break;

        case 'W':
            attributes->weak = YES;
            break;

        case 'P':
            attributes->canBeCollected = YES;
            break;

        case 't':

            // skip over this type encoding
            while (*next != ',' && *next != '\0')
                ++next;

            break;

        default:
                break;
        }
    }

    if (next && *next != '\0') {
    }

    if (!attributes->getter) {
        // use the property name as the getter by default
        attributes->getter = sel_registerName(property_getName(property));
    }

    if (!attributes->setter) {
        const char *propertyName = property_getName(property);
        size_t propertyNameLength = strlen(propertyName);

        // we want to transform the name to setProperty: style
        size_t setterLength = propertyNameLength + 4;

        char setterName[setterLength + 1];
        strncpy(setterName, "set", 3);
        strncpy(setterName + 3, propertyName, propertyNameLength);

        // capitalize property name for the setter
        setterName[3] = (char)toupper(setterName[3]);

        setterName[setterLength - 1] = ':';
        setterName[setterLength] = '\0';

        attributes->setter = sel_registerName(setterName);
    }

    return attributes;

errorOut:
    free(attributes);
    return NULL;
}
