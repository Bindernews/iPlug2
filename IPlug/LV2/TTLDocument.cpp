#include "TTLDocument.h"
#include <cstring>

////////////////
// ITTLWriter //
////////////////

void ITTLWriter::write(const TTLString &text)
{
    write(text.c_str(), text.size());
}

void ITTLWriter::newline(bool indent)
{
    write(TTLDocument::ENDL);
    if (indent) {
        writeIndent();
    }
}

//void ITTLWriter::write(const char *text) { write(text, strlen(text)); }

///////////////////
// FileTTLWriter //
///////////////////

FileTTLWriter::FileTTLWriter(FILE *f)
: mF(f)
, mTab(0)
, mTabSize(2)
{}

FileTTLWriter::~FileTTLWriter()
{
    fclose(mF);
}

void FileTTLWriter::indent(int count)
{
    mTab += count;
    if (mTab < 0) {
        mTab = 0;
    }
}

void FileTTLWriter::writeIndent()
{
    int tabend = mTab * mTabSize;
    for (int i = 0; i < tabend; i++) {
        fputc(' ', mF);
    }
}

void FileTTLWriter::write(const char *text, size_t len)
{
    fwrite(text, len, 1, mF);
}

void FileTTLWriter::setTabSize(size_t ts)
{
    mTabSize = ts;
}


/////////////////
// TTLDocument //
/////////////////

#if 0
#if defined(OS_LINUX)
const char *TTLDocument::ENDL = "\n";
#elif defined(OS_WINDOWS)
const char *TTLDocument::ENDL = "\r\n";
#elif defined(OS_MAC)
const char *TTLDocument::ENDL = "\r";
#endif
#endif
const char *TTLDocument::ENDL = "\n";

TTLDocument::TTLDocument()
{}

TTLDocument& TTLDocument::addPrefix(const TTLString &name, const TTLString &uri)
{
    TTLString s;
    s.append("@prefix ");
    s.append(name);
    s.append(": ");
    s.append(uri);
    mPrefixes.push_back(s);
    return *this;
}

TTLSubject* TTLDocument::subject(const TTLString &sub)
{
    auto it = mSubjectMap.find(sub);
    if (it == mSubjectMap.end()) {
        auto subPtr = new TTLSubject(sub);
        mSubjects.push_back(subPtr);
        mSubjectMap[sub] = mSubjects.size() - 1;
        return subPtr;
    } else {
        return mSubjects[it->second];
    }
}

void TTLDocument::write(ITTLWriter &f)
{
    for (auto &pre : mPrefixes) {
        f.write(pre);
        f.write(" .");
        f.write(ENDL);
    }
    f.write(ENDL);

    for (auto &sub : mSubjects) {
        f.write(sub->getName());
        f.write(ENDL);
        sub->write(f, true);
        f.write(ENDL);
    }
}



///////////////
// TTLObject //
///////////////

TTLObject::TTLObject()
{
    mType = 0;
    mStrVal = nullptr;
    mSubjVal = nullptr;
}

TTLObject::TTLObject(const TTLString &text)
{
    mType = 1;
    mStrVal = std::unique_ptr<TTLString>(new TTLString(text));
    mSubjVal = nullptr;
}

TTLObject::TTLObject(TTLSubject *sub)
{
    mType = 2;
    mStrVal = nullptr;
    mSubjVal = std::unique_ptr<TTLSubject>(sub);
}

void TTLObject::write(ITTLWriter &f)
{
    if (mType == 1) {
        f.write(*mStrVal);
    }
    else if (mType == 2) {
        f.write("[");
        f.newline();
        mSubjVal->write(f, false);
        f.writeIndent();
        f.write("]");
    }
}


////////////////
// TTLSubject //
////////////////

TTLSubject::TTLSubject()
: mName()
{}

TTLSubject::TTLSubject(const TTLString &name)
: mName(name)
{}

TTLSubject& TTLSubject::reserve(const TTLString &verb)
{
    ensureVerb(verb);
    return *this;
}

TTLSubject& TTLSubject::add(const TTLString &verb, const TTLString &value)
{
    auto &vval = ensureVerb(verb);
    vval.values.push_back(TTLObject(value));
    return *this;
}

TTLSubject& TTLSubject::add(const TTLString &verb, TTLSubject *sub)
{
    auto &vval = ensureVerb(verb);
    vval.values.push_back(TTLObject(sub));
    return *this;
}

TTLSubject& TTLSubject::setMultilineThreshold(const TTLString &verb, int thresh)
{
    auto &vval = ensureVerb(verb);
    vval.multilineThreshold = thresh;
    return *this;
}

TTLSubject::VerbVal& TTLSubject::ensureVerb(const TTLString &verb)
{
    auto it = mVerbMap.find(verb);
    if (it == mVerbMap.end()) {
        mVerbList.push_back(VerbVal { name: verb, multilineThreshold: 6 });
        mVerbMap[verb] = mVerbList.size() - 1;
    }
    return mVerbList[mVerbMap[verb]];
}

void TTLSubject::write(ITTLWriter &f, bool endTriplet)
{
    f.indent(1);
    for (auto &it : mVerbList) {
        // Skip any keys without values
        if (it.values.size() == 0) {
            continue;
        }

        bool multiline = it.multilineThreshold > 0 && it.values.size() > it.multilineThreshold;

        // Write the key and a space
        f.writeIndent();
        f.write(it.name);
        f.write(" ");

        if (multiline) {
            f.indent(1);
        }

        const char *sep = multiline ? " ," : ", ";

        // Write the "end" of the previous entry at the start of the next one
        // because it's easy to know if we're at the "first" item but difficult
        // to know if we're at the "last" item when using iterators.
        bool first2 = true;
        for (auto &it2 : it.values) {
            if (!first2) {
                f.write(sep);
            }
            first2 = false;

            if (multiline) {
                f.newline(true);
            }

            it2.write(f);
        }

        f.write(" ;");

        if (multiline) {
            f.indent(-1);
        }

        f.newline();
    }
    if (endTriplet) {
        f.writeIndent();
        f.write(".");
        f.newline();
    }
    f.indent(-1);
}

