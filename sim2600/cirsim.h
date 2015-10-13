#pragma once

#include <vector>

void test(void); 


class CPPGroup
{
public:
    
    std::vector<int> gvec;
    CPPGroup() {
        gvec.reserve(10); 

    }

    int contains(int x ) {
        for(int i = 0; i < gvec.size(); ++i) {
            if (x == gvec[i]) {
                return true;
            } 
        }
        return false; 

    }

    void insert(int x) {
        if(!contains(x)) {
            gvec.push_back(x); 
        }


    }
}; 
